# frozen_string_literal: true

require 'json'
require 'openssl'
require 'irasutoya'
require 'irasutoya/cli/detail_page_fetch'
require 'irasutoya/cli/html_page'
require 'irasutoya/cli/page_url'
require 'irasutoya/cli/transfer_deadline'

module Irasutoya
  module Cli
    class Illustration < Irasutoya::Irasuto
      extend HtmlPage

      FEED_TIMEOUT = 60
      MAX_FEED_BYTES = 64 * 1024
      CONNECTION_ERRORS = [
        EOFError, SocketError, OpenSSL::SSL::SSLError,
        Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH
      ].freeze

      class FeedError < StandardError; end

      def self.random
        url = PageUrl.parse(random_url).to_s
        DetailPageFetch.fetch(Irasutoya::IrasutoLink.new(title: nil, show_url: url))
      end

      def self.parse_list_page(document:)
        document.css('.box').each do |card|
          url_anchor, title_anchor = card.css('a')
          card.remove_class('box') unless title_anchor && url_anchor['href']
        end
        super
      end

      class << self
        private

        def random_url
          feed = decode_random_feed(fetch_random_feed)
          unless feed in { feed: { entry: [Hash => entry, *] } }
            raise FeedError, 'Random selection feed response has no usable entry'
          end

          links = entry[:link]
          alternate = links.find { |link| link in { rel: 'alternate' } } if links.is_a?(Array)
          href = alternate&.fetch(:href, nil)
          return href if href.is_a?(String) && !href.empty?

          raise FeedError, 'Random selection feed response has no usable alternate link'
        end

        def decode_random_feed(body)
          json = body[/\A\s*(?:[a-zA-Z_$][\w$]*\.)*[a-zA-Z_$][\w$]*\s*\((.*)\)\s*;?\s*\z/m, 1]
          raise FeedError, 'Random selection feed response is not valid JSONP' unless json

          JSON.parse(json, symbolize_names: true)
        rescue JSON::ParserError
          raise FeedError, 'Random selection feed response contains invalid JSON'
        end

        def fetch_random_feed
          deadline = TransferDeadline.new
          sessions = Thread.current[:irasutoya_html_sessions]
          deadline.run(FEED_TIMEOUT, FeedError, 'Random selection feed deadline exceeded') do
            request_random_feed(deadline, sessions)
          end
        rescue Timeout::Error
          raise FeedError, 'Random selection feed request timed out'
        rescue *CONNECTION_ERRORS => e
          raise FeedError, connection_error_message(e)
        end

        def request_random_feed(deadline, sessions)
          uri = URI('https://www.irasutoya.com')
          with_page_connection(uri, sessions) do |http|
            deadline.with_connection(http) { read_random_feed(http) }
          end
        end

        def connection_error_message(error)
          case error
          when EOFError then 'Random selection feed connection closed unexpectedly'
          when SocketError then 'Random selection feed could not resolve host'
          when OpenSSL::SSL::SSLError then 'Random selection feed TLS handshake failed'
          else "Random selection feed connection failed: #{error.message}"
          end
        end

        def read_random_feed(http)
          limit_error = FeedError.new("Random selection feed response exceeds the #{MAX_FEED_BYTES}-byte limit")
          body = nil
          http.request_get(random_api_path, 'Accept-Encoding' => 'identity') do |response|
            unless response.is_a?(Net::HTTPSuccess)
              raise FeedError, "Random selection feed request failed (HTTP #{response.code})"
            end

            body = ResponseBody.read(response, http, max_bytes: MAX_FEED_BYTES, limit_error: limit_error)
          end
          body
        end
      end
    end
  end
end
