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
          copy_image(uri, file)
          file.flush
          link_image(file.path, filename)
        end
      end

      def copy_image(uri, file)
        uri.open('Accept-Encoding' => 'identity') do |source|
          length = source.meta['content-length'] unless source.meta.key?('transfer-encoding')
          bytes = IO.copy_stream(source, file)
          raise EOFError, "expected #{length} bytes, received #{bytes}" if length && bytes < length.to_i
        end
      rescue EOFError => e
        raise Thor::Error, "Incomplete image download from #{uri}: #{e.message}"
      end

      def link_image(source, filename)
        path = File.join(@directory, filename)
        File.link(source, path)
        path
      rescue Errno::EEXIST
        link_with_suffix(source, filename)
      end

      def link_with_suffix(source, filename)
        extension = File.extname(filename)
        stem = File.basename(filename, extension)
        1.step do |index|
          return link_candidate(source, stem, "-#{index}#{extension}")
        rescue Errno::EEXIST
          next
        end
      end

      def link_candidate(source, stem, ending)
        path = File.join(@directory, "#{stem}#{ending}")
        File.link(source, path)
        path
      rescue Errno::ENAMETOOLONG
        raise if stem.empty?

        stem = stem[0...-1]
        retry
      end
    end
  end
end
