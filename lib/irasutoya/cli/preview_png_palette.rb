# frozen_string_literal: true

module Irasutoya
  module Cli
    module PreviewPNGPalette
      INDEXED_PALETTE_LIMITS = { 1 => 2, 2 => 4, 4 => 16, 8 => 256 }.freeze

      private

      def store_palette(type, content)
        entries, remainder = content.bytesize.divmod(3)
        invalid_png if palette_chunk || !remainder.zero? || !entries.between?(1, palette_limit)

        self.palette_chunk = ChunkyPNG::Chunk::Palette.new(type, content)
      end

      def store_transparency(type, content)
        invalid_png unless valid_transparency_length?(content.bytesize)

        self.transparency_chunk = ChunkyPNG::Chunk::Transparency.new(type, content)
      end

      def palette_limit
        case header_chunk.color
        when ChunkyPNG::COLOR_INDEXED then INDEXED_PALETTE_LIMITS.fetch(header_chunk.depth, 0)
        when ChunkyPNG::COLOR_TRUECOLOR, ChunkyPNG::COLOR_TRUECOLOR_ALPHA then 256
        else 0
        end
      end

      def valid_transparency_length?(length)
        case header_chunk.color
        when ChunkyPNG::COLOR_INDEXED then palette_chunk && length <= palette_chunk.content.bytesize / 3
        when ChunkyPNG::COLOR_GRAYSCALE then length == 2
        when ChunkyPNG::COLOR_TRUECOLOR then length == 6
        else false
        end
      end
    end
  end
end
