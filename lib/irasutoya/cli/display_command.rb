# frozen_string_literal: true

module Irasutoya
  module Cli
    module DisplayCommand
      private

      def display_search_results(query)
        Illustration.search(query:)
                    .take(3)
                    .lazy
                    .filter_map(&method(:fetch_result))
                    .each(&method(:display))
      end

      def fetch_result(link)
        url = PageUrl.parse(link.show_url).to_s
        link = Irasutoya::IrasutoLink.new(title: link.title, show_url: url) if url != link.show_url
        DetailPageFetch.fetch(link)
      rescue HtmlPage::Error, OpenURI::HTTPError, Timeout::Error, URI::InvalidURIError => e
        warn "warn: Could not fetch result page #{escape_controls(link.show_url)}: #{escape_controls(e.message)}"
        nil
      end

      def display(irasuto)
        return display_jsonl(irasuto) if options[:jsonl]

        display_metadata(irasuto)
        return unless $stdout.tty?

        require 'irasutoya/cli/preview'

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
          @preview_transfer.copy(HttpsUrl.parse(image_url), file, max_bytes: ImageTransfer::MAX_IMAGE_BYTES)
          Preview.show(file.tap(&:rewind))
        end
      rescue ImageTransfer::SizeLimitExceededError
        say "warn: Image preview exceeds the #{ImageTransfer::MAX_IMAGE_BYTES}-byte limit", :yellow
      rescue ImageTransfer::ResponseError, ImageTransfer::TooManyRedirectsError,
             TerminalImage::UnsupportedFormat, TerminalImage::UnsupportedTerminal, URI::InvalidURIError => e
        say "warn: Could not preview #{escape_controls(image_url)}: #{escape_controls(e.message)}", :yellow
      end

      def with_preview_sessions
        ImageTransfer.with_sessions do |transfer|
          @preview_transfer = transfer
          yield
        end
      end
    end
  end
end
