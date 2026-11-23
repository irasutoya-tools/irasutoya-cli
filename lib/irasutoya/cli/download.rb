# frozen_string_literal: true

require 'fileutils'
require 'irasutoya/cli/detail_page_parser'
require 'irasutoya/cli/html_page'
require 'irasutoya/cli/page_url'
require 'irasutoya/cli/terminal_output'
require 'irasutoya/cli/image_transfer'
require 'tempfile'
require 'thor'

module Irasutoya
  module Cli
    class Download
      class SaveError < Error; end

      class TemporaryImage
        def initialize(directory)
          @file = Tempfile.create('.irasutoya-', directory, binmode: true)
        rescue SystemCallError => e
          message = "Could not create temporary image in #{directory}: #{e.message}"
          raise SaveError, TerminalOutput.escape_controls(message)
        end

        def path
          @file.path
        end

        def write(chunk)
          with_io { @file.write(chunk) }
        end

        def flush
          with_io { @file.flush }
        end

        def remove
          begin
            @file.close
          ensure
            unlink
          end
        rescue SystemCallError, IOError => e
          raise SaveError, TerminalOutput.escape_controls("Could not remove temporary image at #{path}: #{e.message}")
        end

        private

        def unlink
          File.unlink(path)
        rescue Errno::ENOENT
          nil
        end

        def with_io
          yield
        rescue SystemCallError, IOError => e
          raise SaveError, TerminalOutput.escape_controls("Could not save image at #{path}: #{e.message}")
        end
      end
      private_constant :TemporaryImage

      def initialize(page_url, directory)
        @page_url = page_url
        @directory = directory
      end

      def save(&report_saved)
        images = page_images
        raise Thor::Error, "No images found on #{@page_url}" if images.empty?

        prepare_directory
        next_suffixes = Hash.new(0)
        ImageTransfer.with_sessions do |transfer|
          images.each { |url| save_image(url, next_suffixes, transfer, &report_saved) }
        end
      end

      private

      def prepare_directory
        FileUtils.mkdir_p(@directory)
      rescue SystemCallError => e
        raise SaveError, TerminalOutput.escape_controls("Could not create output directory #{@directory}: #{e.message}")
      end

      def page_images
        uri = PageUrl.parse(@page_url)

        Irasutoya::IrasutoLink.new(title: nil, show_url: uri.to_s).extend(HtmlPage).fetch_irasuto.image_urls
      rescue URI::InvalidURIError
        raise Thor::Error, 'Provide an Irasutoya illustration page URL printed by search or random.'
      rescue HtmlPage::Error, OpenURI::HTTPError => e
        message = "Could not fetch illustration page #{@page_url}: #{e.message}"
        raise Thor::Error, TerminalOutput.escape_controls(message)
      end

      def save_image(url, next_suffixes, transfer)
        uri = HttpsUrl.parse(url)
        with_temporary_image do |file|
          copy_image(uri, file, transfer)
          yield link_image(file.tap(&:flush).path, image_filename(uri), next_suffixes)
        end
      rescue URI::InvalidURIError => e
        raise Thor::Error, TerminalOutput.escape_controls("Could not download #{url}: #{e.message}")
      rescue ImageTransfer::ResponseError => e
        raise Thor::Error, "Could not fetch image #{url}: #{e.message}"
      end

      def with_temporary_image
        file = TemporaryImage.new(@directory)
        yield file
        completed = true
      ensure
        remove_temporary_image(file, completed)
      end

      def remove_temporary_image(file, completed)
        file&.remove
      rescue SaveError => e
        raise if completed

        warn e.message
      end

      def copy_image(uri, destination, transfer)
        transfer.copy(uri, destination, max_bytes: ImageTransfer::MAX_IMAGE_BYTES)
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
        path = File.join(@directory, "#{stem}#{ending}")
        path.tap { File.link(source, path) }
      rescue Errno::EEXIST
        raise
      rescue Errno::ENAMETOOLONG => e
        raise_save_error(path, e) if stem.empty?

        stem = stem[0...-1]
        retry
      rescue SystemCallError => e
        raise_save_error(path, e)
      end

      def raise_save_error(path, error)
        raise SaveError, TerminalOutput.escape_controls("Could not save image at #{path}: #{error.message}")
      end
    end
  end
end
