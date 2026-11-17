# frozen_string_literal: true

require 'stringio'

RSpec.describe 'ANSI image previews' do
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('TERM_PROGRAM', nil).and_return(nil)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('PATH').and_return('')
  end

  it 'renders a PNG in true color without iTerm2, libsixel, or ImageMagick' do
    png = ChunkyPNG::Image.new(1, 1, ChunkyPNG::Color.rgb(12, 34, 56))

    expect(TerminalImage.encode(StringIO.new(png.to_blob))).to include("\e[38;2;12;34;56m")
  end

  it 'requires ImageMagick to preview a GIF through the ANSI fallback' do
    gif = StringIO.new('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'.unpack1('m0'))

    expect { TerminalImage.encode(gif) }.to raise_error(TerminalImage::UnsupportedFormat, /Install ImageMagick/)
  end
end
