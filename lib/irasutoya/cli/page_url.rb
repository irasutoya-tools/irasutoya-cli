# frozen_string_literal: true

require 'irasutoya/cli/https_url'

module Irasutoya
  module Cli
    module PageUrl
      def self.parse(url)
        uri = HttpsUrl.parse(url)
        return uri if allowed_host?(uri.host) && uri.path.end_with?('.html')

        raise URI::InvalidURIError, 'Page URL must be on irasutoya.com or www.irasutoya.com with a path ending in .html'
      end

      def self.allowed_host?(host)
        %w[irasutoya.com www.irasutoya.com].include?(host.downcase)
      end
    end
  end
end
