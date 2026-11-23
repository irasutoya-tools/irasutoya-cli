# frozen_string_literal: true

module Irasutoya
  module Cli
    module ResponseBody
      def self.read(response, http, max_bytes:, limit_error:)
        length = response.content_length unless response.key?('transfer-encoding')
        raise limit_error if length && length > max_bytes

        collect(response, http, max_bytes, limit_error)
      rescue IOError, Errno::EBADF => e
        raise limit_error if e.cause.equal?(limit_error)

        raise
      end

      def self.collect(response, http, max_bytes, limit_error)
        String.new(encoding: Encoding::BINARY).tap do |body|
          response.read_body do |chunk|
            if body.bytesize + chunk.bytesize > max_bytes
              # Net::HTTP can still read the chunk terminator while unwinding.
              http.finish
              raise limit_error
            end
            body << chunk
          end
        end
      end
      private_class_method :collect
    end
  end
end
