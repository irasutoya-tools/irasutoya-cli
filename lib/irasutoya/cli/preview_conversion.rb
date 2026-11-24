# frozen_string_literal: true

require 'io/wait'
require 'stringio'
require 'tempfile'
require 'irasutoya/cli/process_capture'

module Irasutoya
  module Cli
    module PreviewConversion
      CONVERSION_TIMEOUT = 10
      MAX_PNG_BYTES = 32 * 1024 * 1024
      MAX_VERSION_BYTES = 16 * 1024
      CONVERSION_FAILED = 'ImageMagick could not convert the image to PNG'
      COMMAND_CACHE_KEY = :irasutoya_image_magick_command

      def self.with_command_cache
        previous = Thread.current[COMMAND_CACHE_KEY]
        Thread.current[COMMAND_CACHE_KEY] = {}
        yield
      ensure
        Thread.current[COMMAND_CACHE_KEY] = previous
      end

      def self.png_source(file)
        type = FastImage.type(file)
        return file if type == :png

        command = image_magick_command
        unless command
          raise TerminalImage::UnsupportedFormat,
                "Install ImageMagick to show #{type || 'non-PNG'} images without iTerm2 or libsixel"
        end

        TerminalImage::AnsiEncoder.ensure_within_pixel_limit(*FastImage.size(file))
        convert(command, file)
      end

      class << self
        private

        def image_magick_command
          cache = Thread.current[COMMAND_CACHE_KEY]
          return detect_image_magick_command unless cache
          return cache[:command] if cache.key?(:command)

          cache[:command] = detect_image_magick_command
        end

        def invalidate_image_magick_command!
          Thread.current[COMMAND_CACHE_KEY]&.delete(:command)
        end

        def detect_image_magick_command
          TerminalImage::PngConverter::COMMANDS.filter_map { |name| TerminalImage.send(:which, name) }.find do |path|
            image_magick?(path)
          end
        end

        def image_magick?(command)
          version, status = capture([command, '-version'], MAX_VERSION_BYTES, err: %i[child out])
          status.success? && version.include?('ImageMagick')
        rescue SystemCallError
          false
        end

        def convert(command, file)
          args = [command, *TerminalImage::PngConverter::RESOURCE_LIMITS, '-[0]', 'png:-']
          png, status = with_input(file) { |input| capture(args, MAX_PNG_BYTES, in: input) }
          raise TerminalImage::UnsupportedFormat, CONVERSION_FAILED unless status.success?

          StringIO.new(png)
        rescue SystemCallError
          invalidate_image_magick_command!
          raise TerminalImage::UnsupportedFormat, CONVERSION_FAILED
        end

        def with_input(file)
          file.rewind
          return yield file.to_io if file.respond_to?(:to_io)

          Tempfile.create(binmode: true) do |input|
            IO.copy_stream(file, input)
            yield input.tap(&:rewind)
          end
        end

        def capture(args, max_bytes, **)
          ProcessCapture.new(CONVERSION_TIMEOUT).capture(args, max_bytes, **)
        end
      end
    end
  end
end
