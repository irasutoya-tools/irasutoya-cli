# frozen_string_literal: true

require 'irasutoya'
require 'json'
require 'irasutoya/cli/html_page'

module Irasutoya
  module Cli
    class Illustration < Irasutoya::Irasuto
      extend HtmlPage

      MAX_FEED_BYTES = 64 * 1024

      class FeedError < StandardError; end

      class << self
        private

        def random_url
          jsonp = fetch_random_feed
          JSON.parse(jsonp[/{.+}/]).fetch('feed').fetch('entry').first.fetch('link')
              .find { |link| link['rel'] == 'alternate' }.fetch('href')
        end

        def fetch_random_feed
          limit_error = FeedError.new("Random selection feed response exceeds the #{MAX_FEED_BYTES}-byte limit")
          Net::HTTP.start('www.irasutoya.com', 443, use_ssl: true, max_retries: 0, ignore_eof: false) do |http|
            http.request_get(random_api_path, 'Accept-Encoding' => 'identity') do |response|
              response.value
              return ResponseBody.read(response, http, max_bytes: MAX_FEED_BYTES, limit_error: limit_error)
            end
          end
        end
      end
    end
  end
end
