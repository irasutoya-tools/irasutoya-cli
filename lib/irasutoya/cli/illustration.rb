# frozen_string_literal: true

require 'irasutoya/cli/detail_page_parser'
require 'irasutoya/cli/html_page'

module Irasutoya
  module Cli
    class Illustration < Irasutoya::Irasuto
      extend HtmlPage
    end
  end
end
