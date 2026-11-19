# frozen_string_literal: true

require 'fileutils'
require 'irasutoya'
require 'net/http'
require 'tempfile'
require 'thor'

module Irasutoya
  module Cli
    class Download
      MAX_REDIRECTS = 5

      def initialize(page_url, directory)
        @page_url = page_url
        @directory = directory
      end

      def save
        images = page_images
        raise Thor::Error, "No images found on #{@page_url}" if images.empty?

        FileUtils.mkdir_p(@directory)
        images.each { |url| yield save_image(url) }
      end

      private

      def page_images
        uri = URI.parse(@page_url)
        unless uri.is_a?(URI::HTTP) && %w[irasutoya.com www.irasutoya.com].include?(uri.host&.downcase) &&
               uri.path.end_with?('.html')
          raise Thor::Error, 'Provide an Irasutoya illustration page URL printed by search or random.'
        end

        Irasutoya::IrasutoLink.new(title: nil, show_url: @page_url).fetch_irasuto.image_urls
      rescue URI::InvalidURIError
        raise Thor::Error, 'Provide an Irasutoya illustration page URL printed by search or random.'
      end

      def save_image(url)
        uri = URI.parse(url)
        filename = File.basename(uri.path)
        filename = 'image' if ['', '.', '..', '/'].include?(filename)
        Tempfile.create('.irasutoya-', @directory, binmode: true) do |file|
          stream_image(uri, file)
          file.flush
          link_image(file.path, filename)
        end
      end

      def stream_image(uri, file, redirects_left = MAX_REDIRECTS)
        raise Thor::Error, 'Image download URL must use HTTP or HTTPS' unless uri.is_a?(URI::HTTP)

        redirect = request_image(uri, file)
        return unless redirect
        raise Thor::Error, 'Too many image download redirects' if redirects_left.zero?

        location = uri + redirect
        raise Thor::Error, 'Image redirect must use HTTPS' if uri.scheme == 'https' && location.scheme != 'https'

        stream_image(location, file, redirects_left - 1)
      end

      def request_image(uri, file)
        options = { use_ssl: uri.scheme == 'https', max_retries: 0, ignore_eof: false }
        Net::HTTP.start(uri.hostname, uri.port, **options) do |http|
          http.request_get(uri.request_uri) do |response|
            return response.fetch('location') if %w[301 302 303 307 308].include?(response.code)

            response.value
            response.read_body { |chunk| file.write(chunk) }
          end
        end
        nil
      end

      def link_image(source, filename)
        extension = File.extname(filename)
        stem = File.basename(filename, extension)
        0.step do |index|
          name = index.zero? ? filename : "#{stem}-#{index}#{extension}"
          path = File.join(@directory, name)
          File.link(source, path)
          return path
        rescue Errno::EEXIST
          next
        end
      end
    end
  end
end
