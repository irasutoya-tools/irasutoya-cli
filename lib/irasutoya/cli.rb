# frozen_string_literal: true

require 'open-uri'
require 'tempfile'
require 'timeout'
require 'irasutoya/cli/https_url'
require 'irasutoya/cli/image_transfer'
require 'irasutoya/cli/terminal_output'
require 'irasutoya/cli/version'
require 'thor'

module Irasutoya
  module Cli
    class Runner < Thor
      JSONL_OPTION = { type: :boolean, desc: 'Print one JSON object per result' }.freeze

      def self.exit_on_failure?
        true
      end

      desc 'random', 'Gives you random irasutoya image'
      method_option :jsonl, **JSONL_OPTION
      def random
        require 'irasutoya/cli/illustration'
        with_preview_sessions { display(Illustration.random) }
      end

      desc 'search {query}', 'Shows images from up to three result pages. Each page can contain multiple images.'
      method_option :jsonl, **JSONL_OPTION
      def search(query)
        require 'irasutoya'
        with_preview_sessions do
          Irasutoya::Irasuto
            .search(query:)
            .take(3)
            .lazy
            .filter_map(&method(:fetch_result))
            .each(&method(:display))
        end
      end

      desc 'download PAGE_URL', 'Saves all images from an illustration page'
      method_option :output, type: :string, required: true, banner: 'DIR'
      def download(page_url)
        directory = options[:output]
        raise Thor::Error, 'Provide an output directory with --output.' if directory.empty?

        require 'irasutoya/cli/download'
        Download.new(page_url, directory).save { |path| say "Saved: #{path}" }
      end

      private

      def fetch_result(link)
        url = HttpsUrl.parse(link.show_url).to_s
        link = Irasutoya::IrasutoLink.new(title: link.title, show_url: url) if url != link.show_url
        link.fetch_irasuto
      rescue OpenURI::HTTPError, Timeout::Error, URI::InvalidURIError => e
        warn "warn: Could not fetch result page #{escape_controls(link.show_url)}: #{escape_controls(e.message)}"
        nil
      end

      def display(irasuto)
        return display_jsonl(irasuto) if options[:jsonl]

        require 'irasutoya/cli/preview'

        display_metadata(irasuto)
        return unless $stdout.tty?

        irasuto.image_urls.each(&method(:show_preview))
      end

      def display_jsonl(irasuto)
        require 'json'

        result = { page_url: irasuto.url, title: irasuto.title,
                   description: irasuto.description, image_urls: irasuto.image_urls }
        $stdout.puts JSON.generate(result)
        $stdout.flush
      end

      def display_metadata(irasuto)
        say "Page URL:    #{escape_controls(irasuto.url)}"
        say "Title:       #{escape_controls(irasuto.title)}"
        say "Description: #{escape_controls(irasuto.description)}"
        irasuto.image_urls.each { |image_url| say "Image URL:   #{escape_controls(image_url)}" }
      end

      def escape_controls(value)
        TerminalOutput.escape_controls(value)
      end

      def show_preview(image_url)
        Tempfile.create(binmode: true) do |file|
          download_preview(HttpsUrl.parse(image_url), file)
          Preview.show(file.tap(&:rewind))
        end
      rescue ImageTransfer::SizeLimitExceededError
        say "warn: Image preview exceeds the #{ImageTransfer::MAX_IMAGE_BYTES}-byte limit", :yellow
      rescue ImageTransfer::ResponseError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
             TerminalImage::UnsupportedFormat, TerminalImage::UnsupportedTerminal, URI::InvalidURIError => e
        say "warn: Could not preview #{escape_controls(image_url)}: #{escape_controls(e.message)}", :yellow
      end

      def with_preview_sessions
        ImageTransfer.with_sessions do |transfer|
          @preview_transfer = transfer
          yield
        end
      end

      def download_preview(uri, file)
        @preview_transfer.copy(uri, file, max_bytes: ImageTransfer::MAX_IMAGE_BYTES)
      rescue EOFError => e
        raise ImageTransfer::ResponseError, e.message
      end
    end
  end
end
