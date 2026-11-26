# frozen_string_literal: true

require 'net/http'
require 'open-uri'
require 'timeout'
require 'irasutoya/cli/https_url'
require 'irasutoya/cli/transfer_deadline'
require 'irasutoya/cli/response_body'
require 'irasutoya/cli/session_cache'

module Irasutoya
  module Cli
    module HtmlPage
      MAX_BYTES = 2 * 1024 * 1024
      MAX_REDIRECTS = 5
      FETCH_TIMEOUT = 60
      REDIRECT_CODES = %w[301 302 303 307 308].freeze

      class Error < StandardError; end

      def self.with_sessions
        # Search and detail fetches reach this module through different receivers.
        previous = Thread.current[:irasutoya_html_sessions]
        sessions = Thread.current[:irasutoya_html_sessions] = SessionCache.new
        yield
      ensure
        Thread.current[:irasutoya_html_sessions] = previous
        sessions&.close
      end

      def fetch_page_and_parse(url)
        fetch = TransferDeadline.new
        sessions = Thread.current[:irasutoya_html_sessions]
        fetch.run(FETCH_TIMEOUT, Error, 'HTML fetch deadline exceeded') do
          fetch_html(HttpsUrl.parse(url), fetch, sessions)
        end
      end

      private

      def fetch_html(uri, fetch, sessions)
        MAX_REDIRECTS.downto(0) do |remaining|
          document = nil
          redirect = request_html(uri, fetch, sessions) { |response, http| document = parse_html(response, http) }
          return document if document
          raise Error, 'Too many HTML redirects' if remaining.zero?

          uri = html_redirect(uri, redirect['location'])
        end
      end

      def request_html(uri, fetch, sessions, &)
        with_html_connection(uri, sessions) do |http|
          fetch.with_connection(http) { get_html(http, uri, &) }
        end
      rescue EOFError
        raise Error, "Incomplete HTML response from #{uri}"
      rescue SocketError
        raise Error, "Could not resolve host for #{uri}"
      rescue Timeout::Error
        raise Error, "HTML request timed out for #{uri}"
      rescue OpenURI::HTTPError => e
        raise OpenURI::HTTPError.new("#{e.message} for #{uri}", e.io)
      end

      def get_html(http, uri)
        http.request_get(uri.request_uri, 'Accept-Encoding' => 'identity') do |response|
          return response if REDIRECT_CODES.include?(response.code)

          unless response.is_a?(Net::HTTPSuccess)
            raise OpenURI::HTTPError.new("#{response.code} #{response.message}", nil)
          end

          yield response, http
        end
        nil
      end

      def with_html_connection(uri, sessions, &)
        options = { use_ssl: true, max_retries: 0, ignore_eof: false }
        return Net::HTTP.start(uri.hostname, uri.port, **options, &) unless sessions

        origin = [uri.scheme, uri.hostname.downcase, uri.port]
        http = sessions.fetch(origin) { Net::HTTP.start(uri.hostname, uri.port, **options) }
        redirect = yield http
        # Redirects return before Net::HTTP consumes their bodies.
        completed = redirect.nil?
        redirect
      ensure
        sessions&.discard(origin) unless completed
      end

      def parse_html(response, http)
        limit_error = Error.new("HTML response exceeds the #{MAX_BYTES}-byte limit")
        html = ResponseBody.read(response, http, max_bytes: MAX_BYTES, limit_error: limit_error)
        Nokogiri::HTML.parse(html, nil, html_charset(response))
      end

      def html_charset(response)
        metadata = StringIO.new
        OpenURI::Meta.init(metadata)
        metadata.meta_add_field('content-type', response['content-type']) if response['content-type']
        metadata.charset
      end

      def html_redirect(uri, location)
        HttpsUrl.resolve_redirect(uri, location)
      rescue HttpsUrl::InvalidRedirect
        raise Error, 'Invalid HTTPS redirect for HTML page'
      end
    end
  end
end
