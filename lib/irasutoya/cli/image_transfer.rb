# frozen_string_literal: true

require 'net/http'

module Irasutoya
  module Cli
    class Error < StandardError; end

    module ImageTransfer
      MAX_REDIRECTS = 5
      REDIRECT_CODES = %w[301 302 303 307 308].freeze

      class ResponseError < Error; end

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
          http.request_get(uri.request_uri) do |response|
            return response.fetch('location') if REDIRECT_CODES.include?(response.code)

            response.value
            response.read_body(&on_chunk)
          end
        end
        nil
      rescue Net::HTTPExceptions => e
        raise ResponseError, e.message
      end

      def self.redirect_uri(uri, location)
        target = uri + location
        raise Error, 'Image redirect must use HTTPS' if uri.scheme == 'https' && target.scheme != 'https'

        target
      end

      private_class_method :request, :redirect_uri
    end
  end
end
