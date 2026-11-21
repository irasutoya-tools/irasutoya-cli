# frozen_string_literal: true

require 'net/http'
require 'timeout'

module Irasutoya
  module Cli
    class Error < StandardError; end

    class ImageTransfer
      MAX_REDIRECTS = 5
      TRANSFER_TIMEOUT = 60
      REDIRECT_CODES = %w[301 302 303 307 308].freeze

      class ResponseError < Error; end
      class IncompleteBodyError < ResponseError; end
      class BodyTooLargeError < ResponseError; end
      class InvalidSchemeError < ResponseError; end
      class TooManyRedirectsError < Error; end
      class InsecureRedirectError < ResponseError; end

      class ResponseBody
        def initialize(response, max_bytes)
          @response = response
          @max_bytes = max_bytes
          @length = response.content_length unless response.key?('transfer-encoding')
          @bytes = 0
        end

        def read
          enforce_limit(@length) if @length
          @response.read_body do |chunk|
            @bytes += chunk.bytesize
            enforce_limit(@bytes)
            yield chunk
          end
          validate
        rescue EOFError => e
          raise IncompleteBodyError, incomplete_message || e.message
        end

        private

        def enforce_limit(bytes)
          return unless @max_bytes && bytes > @max_bytes

          raise BodyTooLargeError, "Image response exceeds the #{@max_bytes}-byte limit"
        end

        def validate
          message = incomplete_message
          raise IncompleteBodyError, message if message
          raise ResponseError, 'Empty image response' if @bytes.zero?
        end

        def incomplete_message
          "expected #{@length} bytes, received #{@bytes}" if @length && @bytes < @length
        end
      end
      private_constant :ResponseBody

      def self.fetch(uri, max_bytes: nil, &on_chunk)
        with_sessions { |transfer| transfer.fetch(uri, max_bytes:, &on_chunk) }
      end

      def self.with_sessions
        transfer = new
        yield transfer
      ensure
        transfer&.close
      end

      def initialize
        @sessions = {}
      end

      def fetch(uri, max_bytes: nil, &)
        raise InvalidSchemeError, 'Image URL must use HTTPS' unless uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty?

        Timeout.timeout(TRANSFER_TIMEOUT, ResponseError, 'Image transfer deadline exceeded') do
          fetch_image(uri, max_bytes, &)
        end
      end

      def close
        @sessions.each_value(&:finish)
        @sessions.clear
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
      rescue Net::HTTPExceptions => e
        raise ResponseError, e.message
      ensure
        @sessions.delete(origin)&.finish unless completed
      end

      def stream_image(response, max_bytes, &)
        raise IncompleteBodyError, 'HTTP 206 Partial Content' if response.code == '206'

        response.value
        ResponseBody.new(response, max_bytes).read(&)
      end

      def session(uri, origin)
        options = { use_ssl: true, max_retries: 0, ignore_eof: false }
        @sessions[origin] ||= Net::HTTP.start(uri.hostname, uri.port, **options)
      end

      def empty_body?(response)
        response['content-length'] == '0' && !response.key?('transfer-encoding')
      end

      def redirect_uri(uri, response)
        target = resolve_location(uri, response)
        raise InsecureRedirectError, 'Image redirect must use HTTPS' unless target.is_a?(URI::HTTPS)

        if target.host.to_s.empty? || !(1..65_535).cover?(target.port)
          raise ResponseError, 'Image redirect has an invalid Location header'
        end

        target
      end

      def resolve_location(uri, response)
        location = response['location']&.strip
        raise ResponseError, 'Image redirect is missing a Location header value' if location.nil? || location.empty?

        reference = URI.parse(location)
        if location.start_with?('//') && reference.host.to_s.empty?
          raise ResponseError, 'Image redirect has an invalid Location header'
        end

        uri + reference
      rescue URI::Error
        raise ResponseError, 'Image redirect has an invalid Location header'
      end
    end
  end
end
