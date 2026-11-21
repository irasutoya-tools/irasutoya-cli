# frozen_string_literal: true

require 'uri'

module Irasutoya
  module Cli
    module HttpsUrl
      def self.parse(url)
        uri = URI.parse(url.sub(/\Ahttp:/i, 'https:'))
        raise URI::InvalidURIError, 'URL must use HTTPS' unless uri.is_a?(URI::HTTPS) && uri.host

        uri
      end
    end
  end
end
