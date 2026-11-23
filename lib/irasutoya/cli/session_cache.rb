# frozen_string_literal: true

module Irasutoya
  module Cli
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
        http = @sessions.delete(origin)
        http.finish if http&.started?
      end

      def close
        @sessions.each_value(&:finish)
        @sessions.clear
      end
    end
  end
end
