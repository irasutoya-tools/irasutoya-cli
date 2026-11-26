# frozen_string_literal: true

module Irasutoya
  module Cli
    module DetailPageParser
      def parse_show_page(document:)
        document.css('.entry img:not([src])').remove
        super
      end
    end
  end
end
