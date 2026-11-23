# frozen_string_literal: true

require 'net/http'
require 'open-uri'
require 'timeout'
require 'irasutoya/cli/https_url'

module Irasutoya
  module Cli
    module HtmlPage
      MAX_BYTES = 2 * 1024 * 1024
      MAX_REDIRECTS = 5
      REDIRECT_CODES = %w[301 302 303 307 308].freeze

      class Error < StandardError; end

      def fetch_page_and_parse(url)
        uri = HttpsUrl.parse(url)
        MAX_REDIRECTS.downto(0) do |remaining|
          location = request_html(uri) { |response, http| return parse_html(response, http) }
          raise Error, 'Too many HTML redirects' if remaining.zero?

          uri = html_redirect(uri, location)
        end
      rescue EOFError
        raise Error, "Incomplete HTML response from #{uri}"
      rescue Timeout::Error
        raise Error, "HTML request timed out for #{uri}"
      end

      private

      def request_html(uri)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, max_retries: 0, ignore_eof: false) do |http|
          http.request_get(uri.request_uri, 'Accept-Encoding' => 'identity') do |response|
            return response['location'] if REDIRECT_CODES.include?(response.code)

            unless response.is_a?(Net::HTTPSuccess)
              raise OpenURI::HTTPError.new("#{response.code} #{response.message}", nil)
            end

            yield response, http
          end
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
