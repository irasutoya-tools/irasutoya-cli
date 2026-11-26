# frozen_string_literal: true

require 'irasutoya'
require 'irasutoya/cli/html_page'

module Irasutoya
  module Cli
    class Category < Irasutoya::Category
      extend HtmlPage
      include HtmlPage

      # Irasutoya::Category.all hardcodes `Category.new`, so wrapping it alone would still
      # return plain Irasutoya::Category instances that skip the secure fetcher below.
      def self.all
        super.map { |category| new(title: category.title, list_url: category.list_url) }
      end

      def self.find(title)
        all.find { |category| category.title == title }
      end
    end
  end
end
