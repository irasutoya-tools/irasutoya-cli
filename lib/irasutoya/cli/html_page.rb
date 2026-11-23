# frozen_string_literal: true

require 'net/http'
require 'open-uri'
require 'irasutoya/cli/https_url'

module Irasutoya
  module Cli
    module HtmlPage
      MAX_BYTES = 2 * 1024 * 1024
      MAX_REDIRECTS = 5
      FETCH_TIMEOUT = 60
      REDIRECT_CODES = %w[301 302 303 307 308].freeze

      class Error < StandardError; end

      def fetch_page_and_parse(url)
        fetch = Fetch.new
        fetch.with_deadline { fetch_html(HttpsUrl.parse(url), fetch) }
      end

      private

      class Fetch
        def initialize
          @lock = Mutex.new
        end

        def with_deadline
          worker = Thread.new do
            Thread.current.report_on_exception = false
            yield
          end
          return worker.value if worker.join(FETCH_TIMEOUT)

          raise Error, 'HTML fetch deadline exceeded'
        ensure
          cancel(worker) if worker&.alive?
        end

        def with_connection(http)
          @lock.synchronize { @http = http }
          yield
        ensure
          @lock.synchronize { @http = nil }
        end

        private

        def cancel(worker)
          @lock.synchronize do
            worker.kill
            # Closing the socket unblocks Net::HTTP's chunk terminator read during unwinding.
            close_connection
          end
          worker.join
        rescue StandardError
          # Socket errors raised by the cancelled request must preserve the deadline error.
        end

        def close_connection
          @http.finish if @http&.started?
        rescue IOError
          # The request may have closed the connection as the deadline expired.
        end
      end
      private_constant :Fetch

      def fetch_html(uri, fetch)
        MAX_REDIRECTS.downto(0) do |remaining|
          location = request_html(uri, fetch) { |response, http| return parse_html(response, http) }
          raise Error, 'Too many HTML redirects' if remaining.zero?

          uri = html_redirect(uri, location)
        end
      end

      def request_html(uri, fetch, &)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, max_retries: 0, ignore_eof: false) do |http|
          fetch.with_connection(http) { get_html(http, uri, &) }
        end
      end

      def get_html(http, uri)
        http.request_get(uri.request_uri, 'Accept-Encoding' => 'identity') do |response|
          return response['location'] if REDIRECT_CODES.include?(response.code)

          unless response.is_a?(Net::HTTPSuccess)
            raise OpenURI::HTTPError.new("#{response.code} #{response.message}", nil)
          end

          yield response, http
        end
      end

      def parse_html(response, http)
        check_html_size(response.content_length) unless response.key?('transfer-encoding')
        Nokogiri::HTML.parse(read_html(response, http), nil, html_charset(response))
      rescue IOError, Errno::EBADF => e
        raise e.cause if e.cause.is_a?(Error)

        raise
      end

      def read_html(response, http)
        html = String.new(encoding: Encoding::BINARY)
        response.read_body do |chunk|
          check_html_size(html.bytesize + chunk.bytesize)
          html << chunk
        rescue Error
          # Net::HTTP can still read the chunk terminator while unwinding.
          http.finish
          raise
        end
        html
      end

      def html_charset(response)
        metadata = StringIO.new
        OpenURI::Meta.init(metadata)
        metadata.meta_add_field('content-type', response['content-type']) if response['content-type']
        metadata.charset
      end

      def check_html_size(bytes)
        raise Error, "HTML response exceeds the #{MAX_BYTES}-byte limit" if bytes && bytes > MAX_BYTES
      end

      def html_redirect(uri, location)
        target = uri + location.to_s
        return target if location && target.is_a?(URI::HTTPS) && target.host

        raise Error, 'Invalid HTTPS redirect for HTML page'
      rescue URI::Error
        raise Error, 'Invalid HTTPS redirect for HTML page'
      end
    end
  end
end
