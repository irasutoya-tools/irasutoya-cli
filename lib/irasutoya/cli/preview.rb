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
          png = TerminalImage.send(:png_source, file)
          encoder = TerminalImage::AnsiEncoder
          canvas = PreviewPNG.new.decode(png)
          image = encoder.send(:fit_to_width, canvas, encoder.terminal_width)
          puts encoder.send(:row_pairs, image).map { |top, bottom| encoder.send(:encode_line, top, bottom) }.join("\n")
        end
      end
    end
  end
end
