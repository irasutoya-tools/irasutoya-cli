# frozen_string_literal: true

require 'zlib'

module Irasutoya
  module Cli
    class PreviewPNG < ChunkyPNG::Datastream
      MAX_PIXEL_BYTES = 32 * 1024 * 1024
      MAX_METADATA_BYTES = 1024 * 1024
      CHUNK = ChunkyPNG::Chunk

      def decode(io)
        io.rewind
        self.class.verify_signature!(io)
        read_header(io)
        @metadata_remaining = MAX_METADATA_BYTES
        read_chunks(io)
        ChunkyPNG::Canvas.from_datastream(self)
      rescue ChunkyPNG::Exception, Zlib::Error
        raise TerminalImage::UnsupportedFormat, 'Invalid PNG data'
      end

      def imagedata
        output = String.new(encoding: Encoding::BINARY)
        inflate(data_chunks, [scanline_bytes, MAX_PIXEL_BYTES].min) { |bytes| output << bytes }
        output
      end

      private

      def scanline_bytes
        header = header_chunk
        pass_dimensions(header).sum do |width, height|
          ChunkyPNG::Color.pass_bytesize(header.color, header.depth, width, height)
        end
      end

      def pass_dimensions(header)
        width = header.width
        height = header.height
        return [[width, height]] unless header.interlace == ChunkyPNG::INTERLACING_ADAM7

        ChunkyPNG::Canvas.adam7_pass_sizes(width, height)
      end

      def read_header(io)
        type, content = read_chunk(io)
        invalid_png unless type == 'IHDR' && content.bytesize == 13

        self.header_chunk = CHUNK::Header.read(type, content)
        width = header_chunk.width
        height = header_chunk.height
        invalid_png unless width.positive? && height.positive?

        TerminalImage::AnsiEncoder.ensure_within_pixel_limit(width, height)
      end

      def read_chunks(io)
        loop do
          type, content = read_chunk(io)
          return CHUNK::End.read(type, content) if type == 'IEND'

          store_chunk(type, content)
        end
      end

      def store_chunk(type, content)
        case type
        when 'IDAT' then data_chunks << content
        when 'PLTE' then self.palette_chunk = CHUNK::Palette.new(type, content)
        when 'tRNS' then self.transparency_chunk = CHUNK::Transparency.new(type, content)
        when 'IHDR' then invalid_png
        when 'zTXt', 'iTXt', 'iCCP' then check_metadata(type, content)
        end
      end

      def read_chunk(io)
        length, type = CHUNK.read_bytes(io, 8).unpack('Na4')
        invalid_png if length > io.size - io.pos - 4
        content = CHUNK.read_bytes(io, length)
        CHUNK.verify_crc!(type, content, CHUNK.read_bytes(io, 4).unpack1('N'))
        [type, content]
      end

      def check_metadata(type, content)
        payload = compressed_metadata(type, content)
        return unless payload

        @metadata_remaining = inflate([payload], @metadata_remaining)
      end

      def compressed_metadata(type, content)
        if type == 'iTXt'
          _, compressed, method, _, _, payload = content.unpack('Z*CCZ*Z*a*')
          return if compressed&.zero?

          invalid_png unless compressed == 1
        else
          _, method, payload = content.unpack('Z*Ca*')
        end
        invalid_png unless method&.zero?

        payload
      end

      def inflate(chunks, remaining, &consumer)
        stream = Zlib::Inflate.new
        consume = proc do |bytes|
          remaining = consume_budget(remaining, bytes.bytesize)
          consumer&.call(bytes)
        end
        # Block-form inflation yields output incrementally so the budget can stop decompression.
        chunks.each { |chunk| stream.inflate(chunk, &consume) }
        invalid_png unless stream.finished? && stream.total_in == chunks.sum(&:bytesize)
        remaining
      ensure
        stream&.close
      end

      def consume_budget(remaining, size)
        raise TerminalImage::ImageTooLarge, 'PNG decompression exceeds the preview limit' if size > remaining

        remaining - size
      end

      def invalid_png
        raise TerminalImage::UnsupportedFormat, 'Invalid PNG data'
      end
    end
  end
end
