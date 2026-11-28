# frozen_string_literal: true

require 'net/http'
require 'irasutoya/cli/https_url'
require 'irasutoya/cli/session_cache'
require 'irasutoya/cli/transfer_deadline'

module Irasutoya
  module Cli
    class Error < StandardError; end

    class ImageTransfer
      MAX_IMAGE_BYTES = 10 * 1024 * 1024
      MAX_REDIRECTS = 5
      TRANSFER_TIMEOUT = 60
      REDIRECT_CODES = %w[301 302 303 307 308].freeze

      class ResponseError < Error; end
      class IncompleteBodyError < ResponseError; end
      class SizeLimitExceededError < ResponseError; end
      class InvalidSchemeError < ResponseError; end
      class TooManyRedirectsError < Error; end
      class InsecureRedirectError < ResponseError; end

      class ResponseBody
        def self.read(response, http, max_bytes, &)
          length = checked_length(response, max_bytes)
          bytes = [0]
          stream_chunks(response, http, max_bytes, bytes, &)
          validate(length, bytes[0])
        rescue EOFError => e
          validate(length, bytes[0], eof: e)
        end

        # bytes is a one-element Array so partial progress survives an EOFError unwinding past this method.
        def self.stream_chunks(response, http, max_bytes, bytes)
          response.read_body do |chunk|
            bytes[0] += chunk.bytesize
            enforce_limit(bytes[0], max_bytes, http: http)

            yield chunk
          end
        rescue IOError, Errno::EBADF => e
          # Net::HTTP can still read the chunk terminator while unwinding from the closed connection.
          raise e.cause if e.cause.is_a?(SizeLimitExceededError)

          raise
        end

        def self.checked_length(response, max_bytes)
          return if response.key?('transfer-encoding')

          response.content_length.tap { |length| enforce_limit(length, max_bytes) if length }
        end

        def self.enforce_limit(bytes, max_bytes, http: nil)
          return unless max_bytes && bytes > max_bytes

          # Net::HTTP can still read the chunk terminator while unwinding.
          http&.finish
          raise SizeLimitExceededError, "Image exceeds the #{max_bytes}-byte limit"
        end

        def self.validate(length, bytes, eof: nil)
          raise IncompleteBodyError, "expected #{length} bytes, received #{bytes}" if length && bytes < length
          raise IncompleteBodyError, eof.message if eof
          raise ResponseError, 'Empty image response' if bytes.zero?
        end

        private_class_method :stream_chunks, :checked_length, :enforce_limit, :validate
      end
      private_constant :ResponseBody

      def self.fetch(uri, max_bytes: nil, &on_chunk)
        with_sessions { |transfer| transfer.fetch(uri, max_bytes:, &on_chunk) }
      end

      def self.copy(uri, destination, max_bytes:)
        with_sessions { |transfer| transfer.copy(uri, destination, max_bytes:) }
      end

      def self.with_sessions
        transfer = new
        yield transfer
      ensure
        transfer&.close
      end

      def initialize
        @sessions = SessionCache.new
      end

      def copy(uri, destination, max_bytes:)
        fetch(uri, max_bytes:) { |chunk| destination.write(chunk) }
      end

      def fetch(uri, max_bytes: nil, &)
        raise InvalidSchemeError, 'Image URL must use HTTPS' unless uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty?

        deadline = TransferDeadline.new
        deadline.run(TRANSFER_TIMEOUT, ResponseError, 'Image transfer deadline exceeded') do
          fetch_image(uri, max_bytes, deadline, &)
        end
      end

      def close
        @sessions.close
      end

      private

      def fetch_image(uri, max_bytes, deadline, &)
        MAX_REDIRECTS.downto(0) do |redirects_left|
          redirect = request(uri, max_bytes, deadline, &)
          break unless redirect
          raise TooManyRedirectsError, 'Too many image redirects' if redirects_left.zero?

          uri = redirect_uri(uri, redirect)
        end
      end

      def request(uri, max_bytes, deadline, &on_chunk)
        redirect = nil
        with_connection(uri, deadline) do |http|
          http.request_get(uri.request_uri, 'Accept-Encoding' => 'identity') do |response|
            next stream_image(response, http, max_bytes, &on_chunk) unless REDIRECT_CODES.include?(response.code)

            redirect = response
            return redirect unless empty_body?(response)
          end
        end
        redirect
      end

      def with_connection(uri, deadline, &)
        origin = [uri.scheme, uri.hostname&.downcase, uri.port]
        deadline.with_connection(session(uri, origin), &)
        completed = true
      rescue Net::HTTPExceptions, Net::HTTPHeaderSyntaxError, EOFError, SocketError, OpenSSL::SSL::SSLError,
             Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
             Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPIPE,
             Errno::ETIMEDOUT, Errno::EHOSTUNREACH, Errno::ENETUNREACH => e
        raise ResponseError, e.message
      ensure
        @sessions.discard(origin) unless completed
      end

      def stream_image(response, http, max_bytes, &)
        raise IncompleteBodyError, 'HTTP 206 Partial Content' if response.code == '206'

        response.value
        ResponseBody.read(response, http, max_bytes, &)
      end

      def session(uri, origin)
        options = { use_ssl: true, max_retries: 0, ignore_eof: false }
        @sessions.fetch(origin) { Net::HTTP.start(uri.hostname, uri.port, **options) }
      end

      def empty_body?(response)
        response['content-length'] == '0' && !response.key?('transfer-encoding')
      end

      def redirect_uri(uri, response)
        HttpsUrl.resolve_redirect(uri, response['location'])
      rescue HttpsUrl::MissingLocation
        raise ResponseError, 'Image redirect is missing a Location header value'
      rescue HttpsUrl::InsecureRedirect
        raise InsecureRedirectError, 'Image redirect must use HTTPS'
      rescue HttpsUrl::InvalidRedirect
        raise ResponseError, 'Image redirect has an invalid Location header'
      end
    end
  end
end
