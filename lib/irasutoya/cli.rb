# frozen_string_literal: true

require 'irasutoya/cli/version'
require 'irasutoya'
require 'terminal_image'
require 'thor'

module Irasutoya
  module Cli
    class Error < StandardError; end
    class Runner < Thor
      desc 'random', 'Gives you random irasutoya image'
      def random
        irasuto = Irasutoya::Irasuto.random
        say "Page URL:    #{irasuto.url}"
        say "Title:       #{irasuto.title}"
        say "Description: #{irasuto.description}"
        say "Image URL:   #{irasuto.image_url}"
        TerminalImage.show_url(irasuto.image_url)
      rescue TerminalImage::UnsupportedTerminal
        say 'warn: This terminal is not able to show images inline', :yellow
        say 'warn: Please use iTerm2 or terminal installed libsixel.', :yellow
      end
    end
  end
end
