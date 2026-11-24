# frozen_string_literal: true

require 'irasutoya/cli/detail_page_parser'
require 'irasutoya/cli/html_page'

module Irasutoya
  module Cli
    module DetailPageFetch
      # Prepending to the link's singleton class scopes the parser override to this
      # fetch instead of changing Irasutoya::IrasutoLink's ancestors for the process.
      def self.fetch(link)
        link.extend(HtmlPage)
        link.singleton_class.prepend(DetailPageParser)
        link.fetch_irasuto
      end
    end
  end
end
