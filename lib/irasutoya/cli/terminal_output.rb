# frozen_string_literal: true

module Irasutoya
  module Cli
    module TerminalOutput
      def self.escape_controls(value)
        value.to_s.gsub(/\p{Cc}/) { |character| format('\\x%02X', character.ord) }
      end
    end
  end
end
