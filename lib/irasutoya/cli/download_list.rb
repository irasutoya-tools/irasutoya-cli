# frozen_string_literal: true

require 'net/http'
require 'thor'
require 'irasutoya/cli/terminal_output'

module Irasutoya
  module Cli
    class DownloadList
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

      def process(source)
        failures = 0
        source.each_line.with_index(1) do |line, number|
          url = line.b.strip
          next if url.empty?

          failures += 1 unless process_page(number) { yield url }
        end
        raise Thor::Error, "Failed to download #{failures} page(s)." if failures.positive?
      end

      def process_page(number)
        yield
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
