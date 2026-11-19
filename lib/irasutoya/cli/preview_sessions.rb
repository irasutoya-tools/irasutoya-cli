# frozen_string_literal: true

module Irasutoya
  module Cli
    class PreviewSessions
      REDIRECT_CODES = %w[301 302 303 307 308].freeze

      def initialize
        @sessions = {}
      end

      def get(uri)
        origin = [uri.scheme, uri.hostname&.downcase, uri.port]
        redirect = nil
        session(uri, origin).request_get(uri.request_uri) do |response|
          next yield response unless REDIRECT_CODES.include?(response.code)

          redirect = response.fetch('location')
          return redirect if discard_unread_response?(response, origin)
        end
        redirect
      end

      def close
        @sessions.each_value(&:finish)
        @sessions.clear
      end

      private

      def session(uri, origin)
        @sessions[origin] ||= Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', max_retries: 0)
      end

      def discard_unread_response?(response, origin)
        return false if response['content-length'] == '0' && !response['transfer-encoding']

        @sessions.delete(origin).finish
        true
      end
    end
  end
end
