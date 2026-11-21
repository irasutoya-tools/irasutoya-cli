# frozen_string_literal: true

require 'irasutoya'
require 'irasutoya/cli/https_url'

module Irasutoya
  module Cli
    class Illustration < Irasutoya::Irasuto
      def self.fetch_page_and_parse(url)
        super(HttpsUrl.parse(url).to_s)
      end
    end
  end
end
