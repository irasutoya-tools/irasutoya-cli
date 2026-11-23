# frozen_string_literal: true

require 'net/http'
require 'timeout'
require 'irasutoya/cli/https_url'

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
        def self.read(response, max_bytes)
          bytes = 0
          length = response.content_length unless response.key?('transfer-encoding')
          response.read_body do |chunk|
            bytes += chunk.bytesize
            raise SizeLimitExceededError, "Image exceeds the #{max_bytes}-byte limit" if max_bytes && bytes > max_bytes

            yield chunk
          end
          validate(length, bytes)
        rescue EOFError => e
          validate(length, bytes, eof: e)
        end

        def self.validate(length, bytes, eof: nil)
          raise IncompleteBodyError, "expected #{length} bytes, received #{bytes}" if length && bytes < length
          raise IncompleteBodyError, eof.message if eof
          raise ResponseError, 'Empty image response' if bytes.zero?
        end

        private_class_method :validate
      end
      private_constant :ResponseBody

      class SessionCache
        MAX_SESSIONS = 4

        def initialize
          @sessions = {}
        end

        def fetch(origin)
          # Keep the hash ordered from least to most recently used.
          http = @sessions.delete(origin)
          return @sessions[origin] = http if http

          discard(@sessions.first.first) if @sessions.size >= MAX_SESSIONS
          @sessions[origin] = yield
        end

        def discard(origin)
          @sessions.delete(origin)&.finish
        end

        def close
          @sessions.each_value(&:finish)
          @sessions.clear
        end
      end
      private_constant :SessionCache

      def self.fetch(uri, &on_chunk)
        with_sessions { |transfer| transfer.fetch(uri, &on_chunk) }
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

        Timeout.timeout(TRANSFER_TIMEOUT, ResponseError, 'Image transfer deadline exceeded') do
          fetch_image(uri, max_bytes, &)
        end
      end

      def close
        @sessions.close
      end

      private

      def fetch_image(uri, max_bytes, &)
        MAX_REDIRECTS.downto(0) do |redirects_left|
          redirect = request(uri, max_bytes, &)
          break unless redirect
          raise TooManyRedirectsError, 'Too many image redirects' if redirects_left.zero?

          uri = redirect_uri(uri, redirect)
        end
      end

      def request(uri, max_bytes, &on_chunk)
        redirect = nil
        with_connection(uri) do |http|
          http.request_get(uri.request_uri, 'Accept-Encoding' => 'identity') do |response|
            next stream_image(response, max_bytes, &on_chunk) unless REDIRECT_CODES.include?(response.code)

            redirect = response
            return redirect unless empty_body?(response)
          end
        end
        redirect
      end

      def with_connection(uri)
        origin = [uri.scheme, uri.hostname&.downcase, uri.port]
        yield session(uri, origin)
        completed = true
      rescue Net::HTTPExceptions, EOFError => e
        raise ResponseError, e.message
      ensure
        @sessions.discard(origin) unless completed
      end

      def stream_image(response, max_bytes, &)
        raise IncompleteBodyError, 'HTTP 206 Partial Content' if response.code == '206'

        response.value
        ResponseBody.read(response, max_bytes, &)
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
