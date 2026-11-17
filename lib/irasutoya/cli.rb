# frozen_string_literal: true

require 'open-uri'
require 'irasutoya/cli/version'
require 'irasutoya'
require 'terminal_image'
require 'thor'

module Irasutoya
  module Cli
    class Error < StandardError; end

    class Runner < Thor
      desc 'random', 'Gives you random irasutoya image'
      def random
        display(Irasutoya::Irasuto.random)
      end

      desc 'search {query}', 'Gives you 3 irasutoya images by given query'
      def search(query)
        Irasutoya::Irasuto
          .search(query:)
          .take(3)
          .flat_map(&:fetch_irasuto)
          .compact
          .each(&method(:display))
      end

      private

      def display(irasuto)
        say "Page URL:    #{irasuto.url}"
        say "Title:       #{irasuto.title}"
        say "Description: #{irasuto.description}"
        irasuto.image_urls.each { |image_url| say "Image URL:   #{image_url}" }
        irasuto.image_urls.each(&method(:show_preview))
      end

      def show_preview(image_url)
        TerminalImage.show_url(image_url)
      rescue OpenURI::HTTPError, TerminalImage::UnsupportedTerminal => e
        say "warn: Could not preview #{image_url}: #{e.message}", :yellow
      end
    end
  end
end
