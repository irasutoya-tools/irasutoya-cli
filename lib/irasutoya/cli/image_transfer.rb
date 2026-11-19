# frozen_string_literal: true

require 'net/http'

module Irasutoya
  module Cli
    class Error < StandardError; end

    module ImageTransfer
      MAX_REDIRECTS = 5
      REDIRECT_CODES = %w[301 302 303 307 308].freeze

      class ResponseError < Error; end
      class IncompleteBodyError < ResponseError; end

      def self.fetch(uri, &on_chunk)
        MAX_REDIRECTS.downto(0) do |redirects_left|
          raise Error, 'Image URL must use HTTP or HTTPS' unless uri.is_a?(URI::HTTP)

          redirect = request(uri, &on_chunk)
          break unless redirect
          raise Error, 'Too many image redirects' if redirects_left.zero?

          uri = redirect_uri(uri, redirect)
        end
      end

      def self.request(uri, &on_chunk)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', max_retries: 0) do |http|
          http.request_get(uri.request_uri, 'Accept-Encoding' => 'identity') do |response|
            return response.fetch('location') if REDIRECT_CODES.include?(response.code)

            response.value
            read_body(response, &on_chunk)
          end
        end
        nil
      rescue Net::HTTPExceptions => e
        raise ResponseError, e.message
      end

      def self.read_body(response)
        length = response.content_length unless response.key?('transfer-encoding')
        bytes = 0
        response.read_body do |chunk|
          bytes += chunk.bytesize
          yield chunk
        end
        raise IncompleteBodyError, "expected #{length} bytes, received #{bytes}" if length && bytes < length
      rescue EOFError => e
        raise IncompleteBodyError, e.message
      end

      def self.redirect_uri(uri, location)
        target = uri + location
        raise Error, 'Image redirect must use HTTPS' if uri.scheme == 'https' && target.scheme != 'https'

        target
      end

      private_class_method :request, :read_body, :redirect_uri
    end
  end
end
