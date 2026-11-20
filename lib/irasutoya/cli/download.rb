# frozen_string_literal: true

require 'fileutils'
require 'irasutoya'
require 'net/http'
require 'tempfile'
require 'thor'

module Irasutoya
  module Cli
    class Download
      MAX_REDIRECTS = 64

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
        uri = URI.parse(@page_url)
        unless uri.is_a?(URI::HTTP) && %w[irasutoya.com www.irasutoya.com].include?(uri.host&.downcase) &&
               uri.path.end_with?('.html')
          raise Thor::Error, 'Provide an Irasutoya illustration page URL printed by search or random.'
        end

        Irasutoya::IrasutoLink.new(title: nil, show_url: @page_url).fetch_irasuto.image_urls
      rescue URI::InvalidURIError
        raise Thor::Error, 'Provide an Irasutoya illustration page URL printed by search or random.'
      end

      def save_image(url, next_suffixes)
        uri = URI.parse(url)
        filename = File.basename(uri.path)
        filename = 'image' if ['', '.', '..', '/'].include?(filename)
        Tempfile.create('.irasutoya-', @directory, binmode: true) do |file|
          stream_image(uri, file)
          file.flush
          link_image(file.path, filename, next_suffixes)
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
          http.request_get(uri.request_uri, 'Accept-Encoding' => 'identity') do |response|
            return response.fetch('location') if %w[301 302 303 307 308].include?(response.code)

            response.value
            write_image(response, file, uri)
          end
        end
        nil
      end

      def write_image(response, file, uri)
        response.read_body { |chunk| file.write(chunk) }
      rescue EOFError => e
        length = response.content_length unless response.chunked?
        detail = length ? "expected #{length} bytes, received #{file.pos}" : e.message
        raise Thor::Error, "Incomplete image download from #{uri}: #{detail}"
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
