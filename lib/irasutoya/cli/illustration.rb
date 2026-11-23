# frozen_string_literal: true

require 'irasutoya'
require 'irasutoya/cli/html_page'
require 'irasutoya/cli/page_url'

module Irasutoya
  module Cli
    class Illustration < Irasutoya::Irasuto
      extend HtmlPage

      def self.random
        url = PageUrl.parse(random_url).to_s
        Irasutoya::IrasutoLink.new(title: nil, show_url: url).extend(HtmlPage).fetch_irasuto
      end
    end
  end
end
