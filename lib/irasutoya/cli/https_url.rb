# frozen_string_literal: true

require 'uri'

module Irasutoya
  module Cli
    module HttpsUrl
      class InvalidRedirect < StandardError; end
      class MissingLocation < InvalidRedirect; end
      class InsecureRedirect < InvalidRedirect; end

      def self.parse(url)
        uri = URI.parse(url.sub(/\Ahttp:/i, 'https:'))
        raise URI::InvalidURIError, 'URL must use HTTPS' unless uri.is_a?(URI::HTTPS) && uri.host

        uri
      end

      def self.resolve_redirect(uri, location)
        target = uri + redirect_reference(location)
        raise InsecureRedirect unless target.is_a?(URI::HTTPS)
        raise InvalidRedirect if target.host.to_s.empty? || !(1..65_535).cover?(target.port)

        target
      rescue URI::Error
        raise InvalidRedirect
      end

      def self.redirect_reference(location)
        location = location.to_s.strip
        raise MissingLocation if location.empty?

        reference = URI.parse(location)
        raise InvalidRedirect if location.start_with?('//') && reference.host.to_s.empty?

        reference
      end
      private_class_method :redirect_reference
    end
  end
end
