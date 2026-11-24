# frozen_string_literal: true

module Irasutoya
  module Cli
    class ProcessCapture
      READ_BYTES = 16 * 1024

      def initialize(timeout)
        @deadline = monotonic_time + timeout
      end

      def capture(args, max_bytes, **)
        IO.pipe(binmode: true) do |reader, writer|
          pid = Process.spawn(*args, in: File::NULL, out: writer, err: File::NULL, **)
          writer.close
          output = read_output(reader, max_bytes)
          status = wait_for_exit(pid)
          [output, status]
        ensure
          stop(pid) if pid && !status
        end
      end

      private

      def read_output(reader, max_bytes)
        output = String.new(encoding: Encoding::BINARY)
        loop do
          deadline_exceeded unless reader.wait_readable(remaining_time)
          chunk = reader.readpartial([READ_BYTES, max_bytes - output.bytesize + 1].min)
          output_limit_exceeded(max_bytes) if output.bytesize + chunk.bytesize > max_bytes
          output << chunk
        end
      rescue EOFError
        output
      end

      def wait_for_exit(pid)
        loop do
          remaining = remaining_time
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

      def remaining_time
        remaining = @deadline - monotonic_time
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
