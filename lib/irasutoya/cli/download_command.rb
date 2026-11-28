# frozen_string_literal: true

require 'thor'
require 'irasutoya/cli/download'
require 'irasutoya/cli/download_list'
require 'irasutoya/cli/html_page'
require 'irasutoya/cli/image_transfer'

module Irasutoya
  module Cli
    class DownloadCommand
      def initialize(page_url, input, directory, metadata: false)
        @page_url = page_url
        @input = input
        @directory = directory
        @metadata = metadata
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

        next_suffixes = Hash.new(0)
        metadata_suffixes = Hash.new(0) if @metadata
        HtmlPage.with_sessions do
          DownloadList.new(@input).each do |url|
            download_page(url, transfer, next_suffixes, metadata_suffixes: metadata_suffixes, &)
          end
        end
      end

      def download_page(url, transfer, next_suffixes = Hash.new(0), metadata_suffixes: nil, &)
        Download.new(url, @directory, metadata: @metadata, metadata_suffixes: metadata_suffixes)
                .save(transfer, next_suffixes, &)
      rescue Download::SaveError => e
        raise Thor::Error, e.message
      end
    end
  end
end
