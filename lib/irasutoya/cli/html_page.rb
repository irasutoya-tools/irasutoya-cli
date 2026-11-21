# frozen_string_literal: true

require 'net/http'
require 'open-uri'
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
          location = request_html(uri) { |response| return parse_html(response) }
          raise Error, 'Too many HTML redirects' if remaining.zero?

          uri = html_redirect(uri, location)
        end
      end

      private

      def request_html(uri)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, max_retries: 0, ignore_eof: false) do |http|
          http.request_get(uri.request_uri, 'Accept-Encoding' => 'identity') do |response|
            return response['location'] if REDIRECT_CODES.include?(response.code)

            unless response.is_a?(Net::HTTPSuccess)
              raise OpenURI::HTTPError.new("#{response.code} #{response.message}", nil)
            end

            yield response
          end
        end
      end

      def parse_html(response)
        check_html_size(response.content_length) unless response.key?('transfer-encoding')
        html = String.new(encoding: Encoding::BINARY)
        response.read_body do |chunk|
          check_html_size(html.bytesize + chunk.bytesize)
          html << chunk
        end

        Nokogiri::HTML.parse(html, nil, html_charset(response))
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
