# frozen_string_literal: true

require 'fileutils'
require 'irasutoya'
require 'open-uri'
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
          uri.open { |source| IO.copy_stream(source, file) }
          file.flush
          link_image(file.path, filename)
        end
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
