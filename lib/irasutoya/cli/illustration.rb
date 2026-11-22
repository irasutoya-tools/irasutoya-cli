# frozen_string_literal: true

require 'irasutoya'
require 'irasutoya/cli/html_page'

module Irasutoya
  module Cli
    class Illustration < Irasutoya::Irasuto
      extend HtmlPage
    end
  end
end
