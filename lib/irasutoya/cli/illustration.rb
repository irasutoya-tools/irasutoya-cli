# frozen_string_literal: true

require 'json'
require 'irasutoya/cli/detail_page_parser'
require 'irasutoya/cli/html_page'
require 'irasutoya/cli/page_url'

module Irasutoya
  module Cli
    class Illustration < Irasutoya::Irasuto
      extend HtmlPage
      extend DetailPageParser

      MAX_FEED_BYTES = 64 * 1024

      class FeedError < StandardError; end

      def self.random
        url = PageUrl.parse(random_url).to_s
        Irasutoya::IrasutoLink.new(title: nil, show_url: url).extend(HtmlPage).fetch_irasuto
      end

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
