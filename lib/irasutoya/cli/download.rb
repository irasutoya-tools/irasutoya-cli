# frozen_string_literal: true

require 'fileutils'
require 'irasutoya'
require 'irasutoya/cli/https_url'
require 'irasutoya/cli/terminal_output'
require 'irasutoya/cli/image_transfer'
require 'tempfile'
require 'thor'

module Irasutoya
  module Cli
    class Download
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
      rescue OpenURI::HTTPError => e
        raise Thor::Error, "Could not fetch illustration page #{@page_url}: #{e.message}"
      end

      def save_image(url, next_suffixes)
        uri = HttpsUrl.parse(url)
        Tempfile.create('.irasutoya-', @directory, binmode: true) do |file|
          copy_image(uri, file)
          file.flush
          link_image(file.path, image_filename(uri), next_suffixes)
        end
      rescue URI::InvalidURIError => e
        raise Thor::Error, TerminalOutput.escape_controls("Could not download #{url}: #{e.message}")
      rescue ImageTransfer::ResponseError => e
        raise Thor::Error, "Could not fetch image #{url}: #{e.message}"
      end

      def copy_image(uri, destination)
        ImageTransfer.copy(uri, destination, max_bytes: ImageTransfer::MAX_IMAGE_BYTES)
      rescue ImageTransfer::SizeLimitExceededError
        raise Thor::Error, "Image download exceeds the #{ImageTransfer::MAX_IMAGE_BYTES}-byte limit"
      rescue ImageTransfer::IncompleteBodyError => e
        raise Thor::Error, "Incomplete image download from #{uri}: #{e.message}"
      rescue ImageTransfer::TooManyRedirectsError
        raise Thor::Error, 'Too many image download redirects'
      rescue ImageTransfer::InsecureRedirectError
        raise Thor::Error, 'Image download redirect must use HTTPS'
      end

      def image_filename(uri)
        filename = File.basename(uri.path)
        ['', '.', '..', '/'].include?(filename) ? 'image' : filename
      end

      def link_image(source, filename, next_suffixes)
        extension = File.extname(filename)
        stem = filename.delete_suffix(extension)
        next_suffixes[filename].step do |index|
          ending = index.zero? ? extension : "-#{index}#{extension}"
          path = link_with_stem(source, stem, ending)
          next_suffixes[filename] = index + 1
          return path
        rescue Errno::EEXIST
          next
        end
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
