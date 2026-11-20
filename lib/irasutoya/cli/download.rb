# frozen_string_literal: true

require 'fileutils'
require 'irasutoya'
require 'irasutoya/cli/https_url'
require 'net/http'
require 'tempfile'
require 'thor'

module Irasutoya
  module Cli
    class Download
      MAX_IMAGE_BYTES = 10 * 1024 * 1024
      MAX_REDIRECTS = 5

      def initialize(page_url, directory)
        @page_url = page_url
        @directory = directory
      end

      def save
        images = page_images
        raise Thor::Error, "No images found on #{@page_url}" if images.empty?

        FileUtils.mkdir_p(@directory)
        next_suffixes = Hash.new(0)
        images.each { |url| yield save_image(url, next_suffixes) }
      end

      private

      def page_images
        uri = HttpsUrl.parse(@page_url)
        unless %w[irasutoya.com www.irasutoya.com].include?(uri.host.downcase) && uri.path.end_with?('.html')
          raise Thor::Error, 'Provide an Irasutoya illustration page URL printed by search or random.'
        end

        Irasutoya::IrasutoLink.new(title: nil, show_url: uri.to_s).fetch_irasuto.image_urls
      rescue URI::InvalidURIError
        raise Thor::Error, 'Provide an Irasutoya illustration page URL printed by search or random.'
      end

      def save_image(url, next_suffixes)
        uri = HttpsUrl.parse(url)
        Tempfile.create('.irasutoya-', @directory, binmode: true) do |file|
          download_image(uri, file)
          file.flush
          link_image(file.path, image_filename(uri), next_suffixes)
        end
      rescue URI::InvalidURIError => e
        raise Thor::Error, "Could not download #{url}: #{e.message}"
      rescue EOFError => e
        raise Thor::Error, "Incomplete image download from #{uri}: #{e.message}"
      end

      def image_filename(uri)
        filename = File.basename(uri.path)
        ['', '.', '..', '/'].include?(filename) ? 'image' : filename
      end

      def download_image(uri, file, redirects_left = MAX_REDIRECTS)
        redirect = stream_image(uri, file)
        return unless redirect
        raise Thor::Error, 'Too many image download redirects' if redirects_left.zero?

        location = uri + redirect
        raise Thor::Error, 'Image download redirect must use HTTPS' unless location.is_a?(URI::HTTPS) && location.host

        download_image(location, file, redirects_left - 1)
      end

      def stream_image(uri, file)
        options = { use_ssl: true, max_retries: 0, ignore_eof: false }
        Net::HTTP.start(uri.hostname, uri.port, **options) do |http|
          http.request_get(uri.request_uri, 'Accept-Encoding' => 'identity') do |response|
            return response.fetch('location') if %w[301 302 303 307 308].include?(response.code)

            response.value
            write_image(response, file)
          end
        end
        nil
      end

      def write_image(response, file)
        response.read_body do |chunk|
          if file.pos + chunk.bytesize > MAX_IMAGE_BYTES
            raise Thor::Error, "Image download exceeds the #{MAX_IMAGE_BYTES}-byte limit"
          end

          file.write(chunk)
        end
        verify_image_length(response, file.pos)
      end

      def verify_image_length(response, bytes)
        length = response['content-length'] unless response.key?('transfer-encoding')
        return unless length && bytes < length.to_i

        raise EOFError, "expected #{length} bytes, received #{bytes}"
      end

      def link_image(source, filename, next_suffixes)
        next_suffixes[filename].step do |index|
          path = index.zero? ? link_path(source, filename) : link_with_suffix(source, filename, index)
          next_suffixes[filename] = index + 1
          return path
        rescue Errno::EEXIST
          next
        end
      end

      def link_with_suffix(source, filename, index)
        extension = File.extname(filename)
        stem = File.basename(filename, extension)
        link_with_stem(source, stem, "-#{index}#{extension}")
      end

      def link_with_stem(source, stem, ending)
        link_path(source, "#{stem}#{ending}")
      rescue Errno::ENAMETOOLONG
        raise if stem.empty?

        stem = stem[0...-1]
        retry
      end

      def link_path(source, filename)
        path = File.join(@directory, filename)
        File.link(source, path)
        path
      end
    end
  end
end
