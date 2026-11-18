# frozen_string_literal: true

require 'open-uri'
require 'irasutoya/cli/version'
require 'thor'

module Irasutoya
  module Cli
    class Error < StandardError; end

    class Runner < Thor
      desc 'random', 'Gives you random irasutoya image'
      def random
        require 'irasutoya'
        display(Irasutoya::Irasuto.random)
      end

      desc 'search {query}', 'Shows images from up to three result pages. Each page can contain multiple images.'
      def search(query)
        require 'irasutoya'
        Irasutoya::Irasuto
          .search(query:)
          .take(3)
          .filter_map(&method(:fetch_result))
          .each(&method(:display))
      end

      private

      def fetch_result(link)
        link.fetch_irasuto
      rescue OpenURI::HTTPError => e
        warn "warn: Could not fetch result page #{link.show_url}: #{e.message}"
        nil
      end

      def display(irasuto)
        require 'terminal_image'

        say "Page URL:    #{irasuto.url}"
        say "Title:       #{irasuto.title}"
        say "Description: #{irasuto.description}"
        irasuto.image_urls.each { |image_url| say "Image URL:   #{image_url}" }
        return unless $stdout.tty?

        irasuto.image_urls.each(&method(:show_preview))
      rescue TerminalImage::UnsupportedTerminal
        say 'warn: This terminal is not able to show images inline', :yellow
        say 'warn: Please use iTerm2 or terminal installed libsixel.', :yellow
      end

      def show_preview(image_url)
        require 'open-uri'
        require 'tempfile'

        Tempfile.create(binmode: true) do |file|
          URI.parse(image_url).open { |source| IO.copy_stream(source, file) }
          file.rewind
          TerminalImage.show(file)
        end
      end
    end
  end
end
