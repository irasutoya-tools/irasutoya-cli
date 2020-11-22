# frozen_string_literal: true

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
          .search(query: query)
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
        irasuto.image_urls.each(&TerminalImage.method(:show_url))
      rescue TerminalImage::UnsupportedTerminal
        say 'warn: This terminal is not able to show images inline', :yellow
        say 'warn: Please use iTerm2 or terminal installed libsixel.', :yellow
      end
    end
  end
end
