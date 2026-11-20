# frozen_string_literal: true

require 'irasutoya'
require 'irasutoya/cli/preview'
require 'net/http'
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

    expect { Irasutoya::Cli::Preview.show(StringIO.new(png.to_blob)) }
      .to output(/\e\[38;2;12;34;56m/).to_stdout
  end

  it 'requires ImageMagick to preview a GIF through the ANSI fallback' do
    gif = StringIO.new('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'.unpack1('m0'))

    expect { Irasutoya::Cli::Preview.show(gif) }.to raise_error(TerminalImage::UnsupportedFormat, /Install ImageMagick/)
  end

  describe 'decompression limits' do
    let(:image) { ChunkyPNG::Image.new(1, 1, ChunkyPNG::Color.rgb(12, 34, 56)) }
    let(:valid_png) { image.to_blob }
    let(:urls) { %w[http://example.com/first.png http://example.com/second.png] }

    it 'renders an interlaced PNG and accepts compressed metadata within the budget' do
      interlaced = ChunkyPNG::Image.new(8, 8, image[0, 0])
      datastream = interlaced.to_datastream(interlace: true)
      datastream.other_chunks << ChunkyPNG::Chunk::CompressedText.new('Comment', 'hello')
      expect { Irasutoya::Cli::Preview.show(StringIO.new(datastream.to_blob)) }
        .to output(/\e\[38;2;12;34;56m/).to_stdout
    end

    it 'preserves indexed colors and transparency' do
      indexed = ChunkyPNG::Image.new(2, 1, ChunkyPNG::Color::TRANSPARENT)
      indexed[1, 0] = image[0, 0]
      png = indexed.to_blob(color_mode: ChunkyPNG::COLOR_INDEXED)

      expect { Irasutoya::Cli::Preview.show(StringIO.new(png)) }
        .to output(/\e\[49m \e\[38;2;12;34;56m/).to_stdout
    end

    it 'delegates to the iTerm2 renderer when detected' do
      allow(ENV).to receive(:fetch).with('TERM_PROGRAM', nil).and_return('iTerm.app')

      expect { Irasutoya::Cli::Preview.show(StringIO.new(valid_png)) }
        .to output(/\e\]1337;File=inline=1;/).to_stdout
    end

    it 'reports invalid PNG chunks as an unsupported preview' do
      broken = valid_png.dup
      broken.setbyte(29, broken.getbyte(29) ^ 1)

      expect { Irasutoya::Cli::Preview.show(StringIO.new(broken)) }
        .to raise_error(TerminalImage::UnsupportedFormat, 'Invalid PNG data')
    end

    it 'rejects a chunk whose declared length exceeds the bytes available' do
      broken = valid_png.dup
      broken[8, 4] = [broken.bytesize].pack('N')

      expect { Irasutoya::Cli::Preview.show(StringIO.new(broken)) }
        .to raise_error(TerminalImage::UnsupportedFormat, 'Invalid PNG data')
    end

    it 'rejects a second header before decoding the pixels' do
      datastream = image.to_datastream
      datastream.other_chunks << ChunkyPNG::Chunk::Header.new(width: 2, height: 2)

      expect { Irasutoya::Cli::Preview.show(StringIO.new(datastream.to_blob)) }
        .to raise_error(TerminalImage::UnsupportedFormat, 'Invalid PNG data')
    end

    it 'rejects excess scanline data split between IDAT chunks and renders the next preview' do
      datastream = image.to_datastream
      compressed = Zlib::Deflate.deflate("\0" * 32)
      datastream.data_chunks = [compressed.byteslice(0, 5), compressed.byteslice(5..)].map do |part|
        ChunkyPNG::Chunk::ImageData.new('IDAT', part)
      end

      expect_preview_recovery(datastream.to_blob)
    end

    it 'enforces the absolute pixel data budget for valid scanlines' do
      stub_const('Irasutoya::Cli::PreviewPNG::MAX_PIXEL_BYTES', 16)
      larger_png = ChunkyPNG::Image.new(8, 8, image[0, 0]).to_blob(:fast_rgb)

      expect_preview_recovery(larger_png)
    end

    it 'enforces a shared budget across compressed ancillary chunks and renders the next preview' do
      stub_const('Irasutoya::Cli::PreviewPNG::MAX_METADATA_BYTES', 16)
      datastream = image.to_datastream
      datastream.other_chunks << ChunkyPNG::Chunk::CompressedText.new('Comment', 'a' * 10)
      datastream.other_chunks << ChunkyPNG::Chunk::InternationalText.new('Title', 'b' * 10, '', '', 1)

      expect_preview_recovery(datastream.to_blob)
    end

    def expect_preview_recovery(rejected_png)
      result = Irasutoya::Irasuto.new(url: 'http://example.com/', title: 'Preview', description: '', image_urls: urls)
      allow(Irasutoya::Irasuto).to receive(:random).and_return(result)
      http = instance_double(Net::HTTP)
      expect(Net::HTTP).to receive(:start).with('example.com', 80, use_ssl: false, max_retries: 0).once.and_return(http)
      expect(http).to receive(:finish).once
      urls.zip([rejected_png, valid_png]).each do |url, data|
        response = Net::HTTPOK.new('1.1', '200', 'OK')
        allow(response).to receive(:read_body).and_yield(data)
        allow(http).to receive(:request_get).with(URI.parse(url).request_uri).and_yield(response)
      end

      warning = "warn: Could not preview #{urls.first}: PNG decompression exceeds the preview limit"
      expect do
        allow($stdout).to receive(:tty?).and_return(true)
        Irasutoya::Cli::Runner.new([], {}, shell: Thor::Shell::Basic.new).random
      end.to output(/#{Regexp.escape(warning)}\n\e\[38;2;12;34;56m/).to_stdout
    end
  end
end
