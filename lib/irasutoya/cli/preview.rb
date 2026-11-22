# frozen_string_literal: true

require 'terminal_image'
require 'irasutoya/cli/preview_png'

module Irasutoya
  module Cli
    module Preview
      def self.show(file)
        if ENV.fetch('TERM_PROGRAM', nil) == 'iTerm.app' || TerminalImage.send(:which, 'img2sixel')
          TerminalImage.show(file)
        else
          show_ansi(file)
        end
      end

      def self.show_ansi(file)
        png = TerminalImage.send(:png_source, file)
        encoder = TerminalImage::AnsiEncoder
        canvas = PreviewPNG.new.decode(png)
        image = encoder.send(:fit_to_width, canvas, encoder.terminal_width)
        (0...image.height).step(2) do |y|
          bottom = y + 1 < image.height ? image.row(y + 1) : []
          puts encoder.send(:encode_line, image.row(y), bottom)
        end
      end
      private_class_method :show_ansi
    end
  end
end
