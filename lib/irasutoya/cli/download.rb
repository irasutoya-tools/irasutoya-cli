# frozen_string_literal: true

require 'fileutils'
require 'irasutoya'
require 'irasutoya/cli/image_transfer'
require 'tempfile'
require 'thor'

module Irasutoya
  module Cli
    class Download
      MAX_IMAGE_BYTES = 10 * 1024 * 1024

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
      rescue OpenURI::HTTPError => e
        raise Thor::Error, "Could not fetch illustration page #{@page_url}: #{e.message}"
      end

      def save_image(url, next_suffixes)
        uri = URI.parse(url)
        filename = File.basename(uri.path)
        filename = 'image' if ['', '.', '..', '/'].include?(filename)
        Tempfile.create('.irasutoya-', @directory, binmode: true) do |file|
          copy_image(uri, file)
          file.flush
          link_image(file.path, filename, next_suffixes)
        end
      end

      def copy_image(uri, destination)
        ImageTransfer.fetch(uri) { |chunk| write_chunk(destination, chunk) }
      rescue ImageTransfer::IncompleteBodyError => e
        raise Thor::Error, "Incomplete image download from #{uri}: #{e.message}"
      rescue ImageTransfer::InvalidSchemeError
        raise Thor::Error, 'Image download URL must use HTTP or HTTPS'
      rescue ImageTransfer::TooManyRedirectsError
        raise Thor::Error, 'Too many image download redirects'
      rescue ImageTransfer::InsecureRedirectError
        raise Thor::Error, 'Image download redirect must use HTTPS'
      end

      def write_chunk(destination, chunk)
        if destination.pos + chunk.bytesize > MAX_IMAGE_BYTES
          raise Thor::Error, "Image download exceeds the #{MAX_IMAGE_BYTES}-byte limit"
        end

        destination.write(chunk)
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
