# frozen_string_literal: true

require 'etc'
require 'fileutils'
require 'irasutoya'
require 'irasutoya/cli/detail_page_fetch'
require 'irasutoya/cli/html_page'
require 'irasutoya/cli/page_url'
require 'irasutoya/cli/terminal_output'
require 'irasutoya/cli/image_transfer'
require 'json'
require 'tempfile'

module Irasutoya
  module Cli
    class Download
      class SaveError < Error; end

      class TemporaryImage
        IMAGE_SIGNATURES = {
          '.png' => /\A\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR/n,
          '.jpg' => /\A\xff\xd8\xff/n,
          '.gif' => /\AGIF8[79]a/n,
          '.webp' => /\ARIFF.{4}WEBPVP8[ LX]/mn
        }.freeze
        private_constant :IMAGE_SIGNATURES

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

        def image_filename(uri)
          extension = image_extension
          filename = File.basename(uri.path)
          filename = 'image' if ['', '.', '..', '/'].include?(filename)
          original_extension = File.extname(filename)
          original_format = original_extension.downcase.sub(/\A\.jpeg\z/, '.jpg')
          return filename if original_format == extension

          filename.delete_suffix(original_extension) + extension
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

        def image_extension
          header = with_io do
            @file.flush
            @file.rewind
            @file.read(16)
          end
          IMAGE_SIGNATURES.find { |_, signature| signature.match?(header) }&.first ||
            raise(ImageTransfer::ResponseError, 'Unsupported image format')
        end

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

      class ImageLink
        def initialize(directory)
          @directory = directory
        end

        def link(source, stem, ending)
          stem = fit_stem(stem, (@filename_limit ||= filename_limit) - ending.bytesize)
          path = File.join(@directory, "#{stem}#{ending}")
          path.tap { File.link(source, path) }
        rescue Errno::ENAMETOOLONG => e
          raise_save_error(path, e) if stem.empty?

          stem = stem[0...-1]
          retry
        rescue SystemCallError => e
          raise if e.is_a?(Errno::EEXIST)

          raise_save_error(path, e)
        end

        private

        def filename_limit
          return 255 unless defined?(Etc::PC_NAME_MAX)

          File.open(@directory) { |directory| directory.pathconf(Etc::PC_NAME_MAX) } || 255
        rescue SystemCallError, NotImplementedError
          255
        end

        def fit_stem(stem, byte_limit)
          return stem if stem.bytesize <= byte_limit

          bytes = 0
          stem.each_char do |character|
            break if bytes + character.bytesize > byte_limit

            bytes += character.bytesize
          end
          stem.byteslice(0, bytes)
        end

        def raise_save_error(path, error)
          raise SaveError, TerminalOutput.escape_controls("Could not save image at #{path}: #{error.message}")
        end
      end
      private_constant :ImageLink

      class Metadata
        def initialize(directory, image_link)
          @directory = directory
          @image_link = image_link
        end

        def save(illustration, saved_paths, page_uri)
          content = json(illustration, saved_paths)
          write_file(content, page_uri)
        end

        private

        def json(illustration, saved_paths)
          JSON.generate(
            page_url: illustration.url,
            title: illustration.title,
            description: illustration.description,
            image_filenames: saved_paths.map { |path| File.basename(path) }
          )
        end

        def write_file(content, page_uri)
          Tempfile.create('.irasutoya-', @directory) do |file|
            file.write(content)
            file.flush
            link_file(file.path, page_uri)
          end
        rescue SystemCallError, IOError => e
          raise SaveError, TerminalOutput.escape_controls("Could not save metadata in #{@directory}: #{e.message}")
        end

        def link_file(source, page_uri)
          stem = File.basename(page_uri.path, '.html')
          index = 0
          loop do
            ending = index.zero? ? '.json' : "-#{index}.json"
            return @image_link.link(source, stem, ending)
          rescue Errno::EEXIST
            index += 1
          end
        end
      end
      private_constant :Metadata

      def initialize(page_url, directory, metadata: false)
        @page_url = page_url
        @directory = directory
        @metadata = metadata
      end

      def save(transfer, &)
        illustration = fetch_illustration
        images = illustration.image_urls
        raise SaveError, "No images found on #{@page_url}" if images.empty?

        prepare_directory
        next_suffixes = Hash.new(0)
        saved_paths = images.map { |url| save_image(url, next_suffixes, transfer, &) }
        save_metadata(illustration, saved_paths, &) if @metadata
      end

      private

      def prepare_directory
        FileUtils.mkdir_p(@directory)
        @image_link = nil
      rescue SystemCallError => e
        raise SaveError, TerminalOutput.escape_controls("Could not create output directory #{@directory}: #{e.message}")
      end

      def fetch_illustration
        @page_uri = PageUrl.parse(@page_url)
        link = Irasutoya::IrasutoLink.new(title: nil, show_url: @page_uri.to_s)

        DetailPageFetch.fetch(link)
      rescue URI::InvalidURIError
        raise SaveError, 'Provide an Irasutoya illustration page URL printed by search or random.'
      rescue HtmlPage::Error, OpenURI::HTTPError => e
        message = "Could not fetch illustration page #{@page_url}: #{e.message}"
        raise SaveError, TerminalOutput.escape_controls(message)
      end

      def save_image(url, next_suffixes, transfer, &)
        uri = HttpsUrl.parse(url)
        download_and_link_image(uri, next_suffixes, transfer, &)
      rescue URI::InvalidURIError => e
        raise SaveError, TerminalOutput.escape_controls("Could not download #{url}: #{e.message}")
      rescue ImageTransfer::ResponseError => e
        raise SaveError, "Could not fetch image #{url}: #{e.message}"
      end

      def download_and_link_image(uri, next_suffixes, transfer)
        path = nil
        with_temporary_image do |file|
          copy_image(uri, file, transfer)
          path = link_image(file.path, file.image_filename(uri), next_suffixes)
          yield path
        end
        path
      end

      def save_metadata(illustration, saved_paths)
        path = Metadata.new(@directory, image_link).save(illustration, saved_paths, @page_uri)
        yield path
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
        raise SaveError, "Image download exceeds the #{ImageTransfer::MAX_IMAGE_BYTES}-byte limit"
      rescue ImageTransfer::IncompleteBodyError => e
        raise SaveError, "Incomplete image download from #{uri}: #{e.message}"
      rescue ImageTransfer::TooManyRedirectsError
        raise SaveError, 'Too many image download redirects'
      rescue ImageTransfer::InsecureRedirectError
        raise SaveError, 'Image download redirect must use HTTPS'
      end

      def link_image(source, filename, next_suffixes)
        extension = File.extname(filename)
        stem = filename.delete_suffix(extension)
        next_suffixes[filename].step do |index|
          ending = index.zero? ? extension : "-#{index}#{extension}"
          path = image_link.link(source, stem, ending)
          next_suffixes[filename] = index + 1
          return path
        rescue Errno::EEXIST
          next
        end
      end

      def image_link
        @image_link ||= ImageLink.new(@directory)
      end
    end
  end
end
