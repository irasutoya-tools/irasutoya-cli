# frozen_string_literal: true

module Irasutoya
  module Cli
    module DownloadCommand
      private

      def validate_download_target!(page_url, input, directory)
        raise Thor::Error, 'Provide an output directory with --output.' if directory.empty?
        raise Thor::Error, 'Provide either PAGE_URL or --input FILE.' if page_url.nil? == input.nil?
      end

      def download_target(page_url, input, directory, transfer)
        return download_page(page_url, directory, transfer) unless input

        next_suffixes = Hash.new(0)
        DownloadList.new(input).each { |url| download_page(url, directory, transfer, next_suffixes) }
      end

      def download_page(url, directory, transfer, next_suffixes = Hash.new(0))
        Download.new(url, directory).save(transfer, next_suffixes) { |path| say "Saved: #{path}" }
      rescue Download::SaveError => e
        raise Thor::Error, e.message
      end
    end
  end
end
