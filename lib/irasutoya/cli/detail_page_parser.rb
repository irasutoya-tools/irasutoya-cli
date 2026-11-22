# frozen_string_literal: true

require 'irasutoya'

module Irasutoya
  module Cli
    module DetailPageParser
      def parse_show_page(document:)
        document.css('.entry img:not([src])').remove
        super
      end
    end
  end

  IrasutoLink.prepend(Cli::DetailPageParser)
end
