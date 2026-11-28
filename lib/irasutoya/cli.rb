# frozen_string_literal: true

require 'irasutoya/cli/result_presenter'
require 'irasutoya/cli/version'
require 'thor'

module Irasutoya
  module Cli
    class Runner < Thor
      include ResultPresenter

      JSONL_OPTION = { type: :boolean, desc: 'Print one JSON object per result' }.freeze

      def self.exit_on_failure?
        true
      end

      desc 'random', 'Gives you random irasutoya image'
      method_option :jsonl, **JSONL_OPTION
      def random
        require 'irasutoya/cli/illustration'
        with_preview_sessions { display(HtmlPage.with_sessions { Illustration.random }) }
      rescue HtmlPage::Error, Illustration::FeedError, URI::InvalidURIError => e
        raise Thor::Error, e.message
      end

      desc 'search {query}', 'Shows images from up to three result pages. Each page can contain multiple images.'
      method_option :jsonl, **JSONL_OPTION
      def search(query)
        require 'irasutoya/cli/illustration'
        HtmlPage.with_sessions { with_preview_sessions { display_results(Illustration.search(query:)) } }
      rescue HtmlPage::Error => e
        raise Thor::Error, e.message
      end

      desc 'categories', 'Lists irasutoya illustration categories'
      method_option :jsonl, **JSONL_OPTION
      def categories
        require 'irasutoya/cli/category_command'
        HtmlPage.with_sessions { CategoryCommand.new(jsonl: options[:jsonl]).list }
      rescue HtmlPage::Error => e
        raise Thor::Error, e.message
      end

      desc 'browse CATEGORY', 'Shows images from a category. CATEGORY must match a category title exactly.'
      method_option :jsonl, **JSONL_OPTION
      def browse(category_title)
        require 'irasutoya/cli/category_command'
        HtmlPage.with_sessions do
          links = CategoryCommand.new.browse(category_title)
          with_preview_sessions { display_results(links) }
        end
      rescue HtmlPage::Error => e
        raise Thor::Error, e.message
      end

      desc 'download [PAGE_URL]', 'Saves all images from an illustration page or a list of pages'
      method_option :input, type: :string, banner: 'FILE', desc: 'Read page URLs from FILE (use - for stdin)'
      method_option :output, type: :string, required: true, banner: 'DIR'
      method_option :metadata, type: :boolean, desc: 'Save a JSON file with the page metadata and image filenames'
      def download(page_url = nil)
        require 'irasutoya/cli/download_command'

        DownloadCommand.new(page_url, options[:input], options[:output], metadata: options[:metadata])
                       .run { |path| say "Saved: #{path}" }
      end
    end
  end
end
