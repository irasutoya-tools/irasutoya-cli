# frozen_string_literal: true

require 'open-uri'
require 'tempfile'
require 'timeout'
require 'irasutoya/cli/detail_page_fetch'
require 'irasutoya/cli/https_url'
require 'irasutoya/cli/image_transfer'
require 'irasutoya/cli/page_url'
require 'irasutoya/cli/preview_conversion'
require 'irasutoya/cli/terminal_output'

module Irasutoya
  module Cli
    module ResultPresenter
      # Matches Irasutoya::Cli::Preview::RENDERER_CACHE_KEY. Set directly on Thread.current
      # (instead of calling into Preview) so this does not force-load `terminal_image` for
      # commands that never preview an image.
      RENDERER_CACHE_KEY = :irasutoya_preview_renderer

      private

      def display_results(links)
        links.take(3).lazy.filter_map(&method(:fetch_result)).each(&method(:display))
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

      def with_preview_sessions(&block)
        ImageTransfer.with_sessions do |transfer|
          @preview_transfer = transfer
          PreviewConversion.with_command_cache { with_renderer_cache(&block) }
        end
      end

      def with_renderer_cache
        previous = Thread.current[RENDERER_CACHE_KEY]
        Thread.current[RENDERER_CACHE_KEY] = {}
        yield
      ensure
        Thread.current[RENDERER_CACHE_KEY] = previous
      end
    end
  end
end
