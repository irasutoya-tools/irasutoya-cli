# frozen_string_literal: true

require 'open-uri'
require 'tempfile'
require 'timeout'
require 'irasutoya/cli/detail_page_fetch'
require 'irasutoya/cli/display_command'
require 'irasutoya/cli/download_command'
require 'irasutoya/cli/https_url'
require 'irasutoya/cli/image_transfer'
require 'irasutoya/cli/page_url'
require 'irasutoya/cli/preview_conversion'
require 'irasutoya/cli/terminal_output'
require 'irasutoya/cli/version'
require 'thor'

module Irasutoya
  module Cli
    class Runner < Thor
      include DisplayCommand
      include DownloadCommand

      JSONL_OPTION = { type: :boolean, desc: 'Print one JSON object per result' }.freeze

      def self.exit_on_failure?
        true
      end

      desc 'random', 'Gives you random irasutoya image'
      method_option :jsonl, **JSONL_OPTION
      def random
        require 'irasutoya/cli/illustration'
        with_preview_sessions { display(Illustration.random) }
      rescue HtmlPage::Error, Illustration::FeedError, URI::InvalidURIError => e
        raise Thor::Error, e.message
      end

      desc 'search {query}', 'Shows images from up to three result pages. Each page can contain multiple images.'
      method_option :jsonl, **JSONL_OPTION
      def search(query)
        require 'irasutoya/cli/illustration'
        HtmlPage.with_sessions { with_preview_sessions { display_search_results(query) } }
      rescue HtmlPage::Error => e
        raise Thor::Error, e.message
      end

      desc 'download [PAGE_URL]', 'Saves all images from an illustration page or a list of pages'
      method_option :input, type: :string, banner: 'FILE', desc: 'Read page URLs from FILE (use - for stdin)'
      method_option :output, type: :string, required: true, banner: 'DIR'
      def download(page_url = nil)
        require 'irasutoya/cli/download'
        require 'irasutoya/cli/download_list'

        input = options[:input]
        directory = options[:output]
        validate_download_target!(page_url, input, directory)

        ImageTransfer.with_sessions { |transfer| download_target(page_url, input, directory, transfer) }
      end
    end
  end
end
