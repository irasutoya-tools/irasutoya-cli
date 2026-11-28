# frozen_string_literal: true

require 'net/http'
require 'thor'
require 'irasutoya/cli/terminal_output'

module Irasutoya
  module Cli
    class DownloadList
      MAX_LINE_BYTES = 8 * 1024

      def initialize(input)
        @input = input
      end

      def each(&)
        if @input == '-'
          process($stdin, &)
        else
          File.open(@input, 'rb') { |file| process(file, &) }
        end
      rescue SystemCallError, IOError => e
        raise Thor::Error, escape("Could not read URL list #{@input}: #{e.message}")
      end

      private

      def process(source, &)
        failures = 0
        entries(source).with_index(1) do |line, number|
          failures += 1 unless process_entry(line, number, &)
        end
        raise Thor::Error, "Failed to download #{failures} page(s)." if failures.positive?
      end

      def entries(source, &block)
        return enum_for(__method__, source) unless block

        line = ''.b
        each_chunk(source) { |chunk| line = consume_chunk(line, chunk, &block) }
        yield line if line.nil? || !line.empty?
      end

      def each_chunk(source)
        chunk = String.new(encoding: Encoding::BINARY)
        loop do
          source.readpartial(MAX_LINE_BYTES, chunk)
          yield chunk
        end
      rescue EOFError
        nil
      end

      def consume_chunk(line, chunk)
        offset = 0
        while (newline = chunk.index("\n", offset))
          yield append_segment(line, chunk, offset, newline - offset)
          line = ''.b
          offset = newline + 1
        end
        append_segment(line, chunk, offset, chunk.bytesize - offset)
      end

      def append_segment(line, chunk, offset, length)
        # An oversized line stays nil until the next newline.
        return unless line && line.bytesize + length <= MAX_LINE_BYTES

        line << chunk.byteslice(offset, length)
      end

      def process_entry(line, number)
        raise Thor::Error, "URL list entry exceeds #{MAX_LINE_BYTES} bytes." unless line

        url = line.strip
        yield url unless url.empty?
        true
      rescue Thor::Error, Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError,
             Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError => e
        warn escape("Line #{number}: Could not download page: #{e.message}")
        false
      end

      def escape(message)
        TerminalOutput.escape_controls(message.b.force_encoding(Encoding::UTF_8).scrub)
      end
    end
  end
end
