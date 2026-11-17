# frozen_string_literal: true

require 'irasutoya/cli/version'
require 'irasutoya'
require 'net/http'
require 'tempfile'
require 'terminal_image'
require 'thor'
require 'uri'

module Irasutoya
  module Cli
    class Error < StandardError; end

    class Runner < Thor
      MAX_PREVIEW_BYTES = 10 * 1024 * 1024
      MAX_PREVIEW_REDIRECTS = 5
      class PreviewTooLarge < Error; end

      desc 'random', 'Gives you random irasutoya image'
      def random
        display(Irasutoya::Irasuto.random)
      end

      desc 'search {query}', 'Gives you 3 irasutoya images by given query'
      def search(query)
        Irasutoya::Irasuto
          .search(query:)
          .take(3)
          .flat_map(&:fetch_irasuto)
          .compact
          .each(&method(:display))
      end

      private

      def display(irasuto)
        say "Page URL:    #{irasuto.url}"
        say "Title:       #{irasuto.title}"
        say "Description: #{irasuto.description}"
        irasuto.image_urls.each { |image_url| say "Image URL:   #{image_url}" }
        irasuto.image_urls.each(&method(:show_preview))
      rescue TerminalImage::UnsupportedTerminal
        say 'warn: This terminal is not able to show images inline', :yellow
        say 'warn: Please use iTerm2 or terminal installed libsixel.', :yellow
      end

      def show_preview(image_url)
        Tempfile.create(binmode: true) do |file|
          download_preview(URI.parse(image_url), file)
          file.rewind
          TerminalImage.show(file)
        end
      rescue PreviewTooLarge
        say "warn: Image preview exceeds the #{MAX_PREVIEW_BYTES}-byte limit", :yellow
      end

      def download_preview(uri, file, redirects_left = MAX_PREVIEW_REDIRECTS)
        raise Error, 'Image preview URL must use HTTP or HTTPS' unless uri.is_a?(URI::HTTP)

        redirect = stream_preview(uri, file)
        return unless redirect
        raise Error, 'Too many image preview redirects' if redirects_left.zero?

        location = uri + redirect
        raise Error, 'Image preview redirect must use HTTPS' if uri.scheme == 'https' && location.scheme != 'https'

        download_preview(location, file, redirects_left - 1)
      end

      def stream_preview(uri, file)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', max_retries: 0) do |http|
          http.request_get(uri.request_uri) do |response|
            return response.fetch('location') if %w[301 302 303 307 308].include?(response.code)

            response.value
            write_preview(response, file)
          end
        end
        nil
      end

      def write_preview(response, file)
        response.read_body do |chunk|
          raise PreviewTooLarge if file.pos + chunk.bytesize > MAX_PREVIEW_BYTES

          file.write(chunk)
        end
      end
    end
  end
end
