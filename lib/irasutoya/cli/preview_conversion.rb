# frozen_string_literal: true

require 'io/wait'
require 'stringio'
require 'tempfile'

module Irasutoya
  module Cli
    module PreviewConversion
      CONVERSION_TIMEOUT = 10
      MAX_PNG_BYTES = 32 * 1024 * 1024
      MAX_VERSION_BYTES = 16 * 1024
      READ_BYTES = 16 * 1024
      CONVERSION_FAILED = 'ImageMagick could not convert the image to PNG'

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

        def capture(args, max_bytes, **options)
          deadline = monotonic_time + CONVERSION_TIMEOUT
          IO.pipe(binmode: true) do |reader, writer|
            pid = Process.spawn(*args, in: File::NULL, out: writer, err: File::NULL, **options)
            writer.close
            output = read_output(reader, max_bytes, deadline)
            status = wait_for_exit(pid, deadline)
            [output, status]
          ensure
            stop(pid) if pid && !status
          end
        end

        def read_output(reader, max_bytes, deadline)
          output = String.new(encoding: Encoding::BINARY)
          loop do
            deadline_exceeded unless reader.wait_readable(remaining_time(deadline))
            chunk = reader.readpartial([READ_BYTES, max_bytes - output.bytesize + 1].min)
            output_limit_exceeded(max_bytes) if output.bytesize + chunk.bytesize > max_bytes
            output << chunk
          end
        rescue EOFError
          output
        end

        def wait_for_exit(pid, deadline)
          loop do
            remaining = remaining_time(deadline)
            result = Process.wait2(pid, Process::WNOHANG)
            return result.last if result

            sleep([remaining, 0.01].min)
          end
        end

        def stop(pid)
          Process.kill('KILL', pid)
        rescue Errno::ESRCH
          # The child may have exited before the signal was sent.
        ensure
          Process.wait(pid)
        end

        def monotonic_time
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def remaining_time(deadline)
          remaining = deadline - monotonic_time
          deadline_exceeded unless remaining.positive?

          remaining
        end

        def deadline_exceeded
          raise TerminalImage::UnsupportedFormat, 'ImageMagick preview deadline exceeded'
        end

        def output_limit_exceeded(max_bytes)
          raise TerminalImage::UnsupportedFormat, "ImageMagick output exceeds the #{max_bytes}-byte preview limit"
        end
      end
    end
  end
end
