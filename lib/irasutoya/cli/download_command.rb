# frozen_string_literal: true

require 'thor'
require 'irasutoya/cli/download'
require 'irasutoya/cli/download_list'
require 'irasutoya/cli/html_page'
require 'irasutoya/cli/image_transfer'

module Irasutoya
  module Cli
    class DownloadCommand
      def initialize(page_url, input, directory)
        @page_url = page_url
        @input = input
        @directory = directory
      end

      def run(&)
        validate!
        ImageTransfer.with_sessions { |transfer| download_target(transfer, &) }
      end

      private

      def validate!
        raise Thor::Error, 'Provide an output directory with --output.' if @directory.empty?
        raise Thor::Error, 'Provide either PAGE_URL or --input FILE.' if @page_url.nil? == @input.nil?
      end

      def download_target(transfer, &)
        return download_page(@page_url, transfer, &) unless @input

        HtmlPage.with_sessions do
          DownloadList.new(@input).each { |url| download_page(url, transfer, &) }
        end
      end

      def download_page(url, transfer, &)
        Download.new(url, @directory).save(transfer, &)
      rescue Download::SaveError => e
        raise Thor::Error, e.message
      end
    end
  end
end
