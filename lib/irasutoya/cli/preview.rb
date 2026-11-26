# frozen_string_literal: true

require 'terminal_image'
require 'irasutoya/cli/preview_conversion'
require 'irasutoya/cli/preview_png'
require 'irasutoya/cli/process_capture'

module Irasutoya
  module Cli
    module Preview
      # Shared with Runner#with_renderer_cache in lib/irasutoya/cli.rb, which sets up this
      # cache once per command without needing to require this file (and its `terminal_image`
      # dependency) for commands that never preview an image.
      RENDERER_CACHE_KEY = :irasutoya_preview_renderer
      SIXEL_TIMEOUT = 10
      MAX_SIXEL_BYTES = 32 * 1024 * 1024

      def self.show(file)
        renderer_choice = renderer
        case renderer_choice
        when :iterm2 then TerminalImage.show(file)
        when :ansi then show_ansi(file)
        else show_sixel(file, renderer_choice)
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

      # Feeds the file to img2sixel over its standard input (not a shell-interpolated path) so
      # a TMPDIR containing spaces or shell metacharacters cannot break the command line, and
      # raises instead of printing a blank preview when the subprocess exits unsuccessfully.
      def self.show_sixel(file, command)
        output, status = PreviewConversion.with_input(file) do |input|
          ProcessCapture.new(SIXEL_TIMEOUT).capture([command], MAX_SIXEL_BYTES, in: input)
        end
        raise TerminalImage::UnsupportedTerminal, 'img2sixel could not render the preview' unless status.success?

        puts output
      rescue SystemCallError
        raise TerminalImage::UnsupportedTerminal, 'img2sixel could not render the preview'
      end
      private_class_method :show_sixel

      def self.renderer
        cache = Thread.current[RENDERER_CACHE_KEY]
        return detect_renderer unless cache
        return cache[:renderer] if cache.key?(:renderer)

        cache[:renderer] = detect_renderer
      end
      private_class_method :renderer

      def self.detect_renderer
        return :iterm2 if ENV.fetch('TERM_PROGRAM', nil) == 'iTerm.app'

        TerminalImage.send(:which, 'img2sixel') || :ansi
      end
      private_class_method :detect_renderer
    end
  end
end
