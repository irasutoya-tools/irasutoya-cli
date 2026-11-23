# frozen_string_literal: true

require 'irasutoya/cli/https_url'

module Irasutoya
  module Cli
    module PageUrl
      def self.parse(url)
        uri = HttpsUrl.parse(url)
        return uri if %w[irasutoya.com www.irasutoya.com].include?(uri.host.downcase) && uri.path.end_with?('.html')

        raise URI::InvalidURIError, 'Page URL must be on irasutoya.com or www.irasutoya.com with a path ending in .html'
      end
    end
  end
end
