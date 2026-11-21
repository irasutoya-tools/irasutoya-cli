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
      class InvalidSchemeError < ResponseError; end
      class TooManyRedirectsError < Error; end
      class InsecureRedirectError < ResponseError; end

      def self.fetch(uri, &on_chunk)
        with_sessions { |transfer| transfer.fetch(uri, &on_chunk) }
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

      def fetch(uri, &)
        raise InvalidSchemeError, 'Image URL must use HTTPS' unless uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty?

        Timeout.timeout(TRANSFER_TIMEOUT, ResponseError, 'Image transfer deadline exceeded') { fetch_image(uri, &) }
      end

      def close
        @sessions.each_value(&:finish)
        @sessions.clear
      end

      private

      def fetch_image(uri, &)
        MAX_REDIRECTS.downto(0) do |redirects_left|
          redirect = request(uri, &)
          break unless redirect
          raise TooManyRedirectsError, 'Too many image redirects' if redirects_left.zero?

          uri = redirect_uri(uri, redirect)
        end
      end

      def request(uri, &on_chunk)
        redirect = nil
        with_connection(uri) do |http|
          http.request_get(uri.request_uri, 'Accept-Encoding' => 'identity') do |response|
            next stream_image(response, &on_chunk) unless REDIRECT_CODES.include?(response.code)

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

      def stream_image(response, &)
        raise IncompleteBodyError, 'HTTP 206 Partial Content' if response.code == '206'

        response.value
        read_body(response, &)
      end

      def session(uri, origin)
        options = { use_ssl: true, max_retries: 0, ignore_eof: false }
        @sessions[origin] ||= Net::HTTP.start(uri.hostname, uri.port, **options)
      end

      def empty_body?(response)
        response['content-length'] == '0' && !response.key?('transfer-encoding')
      end

      def read_body(response)
        length = response.content_length unless response.key?('transfer-encoding')
        bytes = 0
        response.read_body do |chunk|
          bytes += chunk.bytesize
          yield chunk
        end
        validate_body(length, bytes)
      rescue EOFError => e
        raise IncompleteBodyError, "expected #{length} bytes, received #{bytes}" if length && bytes < length

        raise IncompleteBodyError, e.message
      end

      def validate_body(length, bytes)
        raise IncompleteBodyError, "expected #{length} bytes, received #{bytes}" if length && bytes < length
        raise ResponseError, 'Empty image response' if bytes.zero?
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
