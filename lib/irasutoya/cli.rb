# frozen_string_literal: true

require 'open-uri'
require 'tempfile'
require 'irasutoya/cli/image_transfer'
require 'irasutoya/cli/version'
require 'thor'

module Irasutoya
  module Cli
    class Runner < Thor
      MAX_PREVIEW_BYTES = 10 * 1024 * 1024
      class PreviewTooLarge < Error; end

      def self.exit_on_failure?
        true
      end

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
          .lazy
          .filter_map(&method(:fetch_result))
          .each(&method(:display))
      end

      desc 'download PAGE_URL', 'Saves all images from an illustration page'
      method_option :output, type: :string, required: true, banner: 'DIR'
      def download(page_url)
        require 'irasutoya/cli/download'
        Download.new(page_url, options[:output]).save { |path| say "Saved: #{path}" }
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

        display_metadata(irasuto)
        return unless $stdout.tty?

        irasuto.image_urls.each(&method(:show_preview))
      end

      def display_metadata(irasuto)
        say "Page URL:    #{escape_controls(irasuto.url)}"
        say "Title:       #{escape_controls(irasuto.title)}"
        say "Description: #{escape_controls(irasuto.description)}"
        irasuto.image_urls.each { |image_url| say "Image URL:   #{escape_controls(image_url)}" }
      end

      def escape_controls(value)
        value.to_s.gsub(/\p{Cc}/) { |character| format('\\x%02X', character.ord) }
      end

      def show_preview(image_url)
        Tempfile.create(binmode: true) do |file|
          download_preview(URI.parse(image_url), file)
          file.rewind
          TerminalImage.show(file)
        end
      rescue PreviewTooLarge
        say "warn: Image preview exceeds the #{MAX_PREVIEW_BYTES}-byte limit", :yellow
      rescue ImageTransfer::ResponseError, TerminalImage::UnsupportedFormat, TerminalImage::UnsupportedTerminal => e
        say "warn: Could not preview #{image_url}: #{e.message}", :yellow
      end

      def download_preview(uri, file)
        ImageTransfer.fetch(uri) do |chunk|
          raise PreviewTooLarge if file.pos + chunk.bytesize > MAX_PREVIEW_BYTES

          file.write(chunk)
        end
      end
    end
  end
end
