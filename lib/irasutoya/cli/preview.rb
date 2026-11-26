# frozen_string_literal: true

require 'terminal_image'
require 'irasutoya/cli/preview_conversion'
require 'irasutoya/cli/preview_png'

module Irasutoya
  module Cli
    module Preview
      # Shared with ResultPresenter#with_renderer_cache in lib/irasutoya/cli/result_presenter.rb,
      # which sets up this cache once per command without needing to require this file (and its
      # `terminal_image` dependency) for commands that never preview an image.
      RENDERER_CACHE_KEY = :irasutoya_preview_renderer

      def self.show(file)
        if terminal_image_renderer?
          TerminalImage.show(file)
        else
          show_ansi(file)
        end
      end

      def self.show_ansi(file)
        png = PreviewConversion.png_source(file)
        encoder = TerminalImage::AnsiEncoder
        canvas = PreviewPNG.new.decode(png)
        image = encoder.send(:fit_to_width, canvas, encoder.terminal_width)
        (0...image.height).step(2) do |y|
          bottom = y + 1 < image.height ? image.row(y + 1) : []
          puts encoder.send(:encode_line, image.row(y), bottom)
        end
      end
      private_class_method :show_ansi

      def self.terminal_image_renderer?
        cache = Thread.current[RENDERER_CACHE_KEY]
        return detect_terminal_image_renderer unless cache
        return cache[:terminal_image] if cache.key?(:terminal_image)

        cache[:terminal_image] = detect_terminal_image_renderer
      end
      private_class_method :terminal_image_renderer?

      def self.detect_terminal_image_renderer
        ENV.fetch('TERM_PROGRAM', nil) == 'iTerm.app' || TerminalImage.send(:which, 'img2sixel')
      end
      private_class_method :detect_terminal_image_renderer
    end
  end
end
