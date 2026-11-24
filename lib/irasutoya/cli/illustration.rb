# frozen_string_literal: true

require 'json'
require 'irasutoya'
require 'irasutoya/cli/detail_page_fetch'
require 'irasutoya/cli/html_page'
require 'irasutoya/cli/http_deadline'
require 'irasutoya/cli/page_url'

module Irasutoya
  module Cli
    class Illustration < Irasutoya::Irasuto
      extend HtmlPage

      FEED_TIMEOUT = 60
      MAX_FEED_BYTES = 64 * 1024

      class FeedError < StandardError; end

      def self.random
        url = PageUrl.parse(random_url).to_s
        DetailPageFetch.fetch(Irasutoya::IrasutoLink.new(title: nil, show_url: url))
      end

      class << self
        private

        def random_url
          jsonp = fetch_random_feed
          JSON.parse(jsonp[/{.+}/]).fetch('feed').fetch('entry').first.fetch('link')
              .find { |link| link['rel'] == 'alternate' }.fetch('href')
        end

        def fetch_random_feed
          deadline_error = FeedError.new('Random selection feed deadline exceeded')
          deadline = HttpDeadline.new(FEED_TIMEOUT, deadline_error)
          deadline.run do
            Net::HTTP.start('www.irasutoya.com', 443, use_ssl: true, max_retries: 0, ignore_eof: false) do |http|
              deadline.with_connection(http) { read_random_feed(http) }
            end
          end
        rescue Timeout::Error
          raise FeedError, 'Random selection feed request timed out'
        end

        def read_random_feed(http)
          limit_error = FeedError.new("Random selection feed response exceeds the #{MAX_FEED_BYTES}-byte limit")
          http.request_get(random_api_path, 'Accept-Encoding' => 'identity') do |response|
            response.value
            return ResponseBody.read(response, http, max_bytes: MAX_FEED_BYTES, limit_error: limit_error)
          end
        end
      end
    end
  end
end
