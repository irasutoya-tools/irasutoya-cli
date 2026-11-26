# frozen_string_literal: true

require 'irasutoya'
require 'irasutoya/cli/illustration'
require 'irasutoya/cli/preview'
require 'net/http'
require 'rbconfig'
require 'stringio'
require 'tmpdir'

RSpec.describe 'ANSI image previews' do
  let(:gif) { 'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'.unpack1('m0') }

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

  [4, 5].each do |height|
    it "matches the encoder's output for a #{height}-row PNG" do
      image = ChunkyPNG::Image.new(2, height, ChunkyPNG::Color::TRANSPARENT)
      height.times { |y| image[y % 2, y] = ChunkyPNG::Color.rgb(12, 34, y) }
      png = StringIO.new(image.to_blob)
      encoder = TerminalImage::AnsiEncoder
      allow(encoder).to receive(:terminal_width).and_return(80)
      expected = "#{encoder.encode(png)}\n"

      expect { Irasutoya::Cli::Preview.show(png) }.to output(expected).to_stdout
    end
  end

  it 'writes each line before encoding the next pair of rows in a tall PNG' do
    image = ChunkyPNG::Image.new(1, 2000, ChunkyPNG::Color.rgb(12, 34, 56))
    line = "\e[38;2;12;34;56m\e[48;2;12;34;56m▀\e[0m\n"
    lines_encoded = 0
    allow(TerminalImage::AnsiEncoder).to receive(:encode_line).and_wrap_original do |encode, top, bottom|
      expect($stdout.pos).to eq(lines_encoded * line.bytesize)
      lines_encoded += 1
      encode.call(top, bottom)
    end

    expect { Irasutoya::Cli::Preview.show(StringIO.new(image.to_blob)) }
      .to output(line * 1000).to_stdout
  end

  it 'requires ImageMagick to preview a GIF through the ANSI fallback' do
    expect { Irasutoya::Cli::Preview.show(StringIO.new(gif)) }
      .to raise_error(TerminalImage::UnsupportedFormat, /Install ImageMagick/)
  end

  describe 'bounded previews' do
    let(:image) { ChunkyPNG::Image.new(1, 1, ChunkyPNG::Color.rgb(12, 34, 56)) }
    let(:valid_png) { image.to_blob }
    let(:urls) { %w[http://example.com/first.png http://example.com/second.png] }

    it 'renders a converted GIF whose PNG output fits the byte budget' do
      stub_const('Irasutoya::Cli::PreviewConversion::MAX_PNG_BYTES', valid_png.bytesize)
      with_converter("STDOUT.binmode; STDOUT.write(#{valid_png.dump})") do
        expect { Irasutoya::Cli::Preview.show(StringIO.new(gif)) }
          .to output(/\e\[38;2;12;34;56m/).to_stdout
      end
    end

    ['sleep 10', "STDOUT.reopen(File::NULL, 'w'); sleep 10"].each do |stall|
      it "reaps a stalled converter (#{stall}) and renders the next preview" do
        stub_const('Irasutoya::Cli::PreviewConversion::CONVERSION_TIMEOUT', 2)
        with_converter(stall) do |pid_file|
          expect_preview_recovery(gif, 'ImageMagick preview deadline exceeded')
          expect_reaped(pid_file)
        end
      end
    end

    it 'reaps a converter that exceeds the byte budget and renders the next preview' do
      stub_const('Irasutoya::Cli::PreviewConversion::MAX_PNG_BYTES', 64)
      with_converter("STDOUT.sync = true; STDOUT.write('a' * 65); sleep 10") do |pid_file|
        expect_preview_recovery(gif, 'ImageMagick output exceeds the 64-byte preview limit')
        expect_reaped(pid_file)
      end
    end

    it 'reports ImageMagick as unavailable when the detected executable cannot be started' do
      allow(TerminalImage).to receive(:which).and_call_original
      allow(TerminalImage).to receive(:which).with('magick').and_return(File.join(__dir__, 'missing-magick'))

      expect { Irasutoya::Cli::Preview.show(StringIO.new(gif)) }
        .to raise_error(TerminalImage::UnsupportedFormat, /Install ImageMagick/)
    end

    it 'warns and renders the next preview when ImageMagick disappears after its version check' do
      with_converter('abort', remove_after_version: true) do
        expect_preview_recovery(gif, 'ImageMagick could not convert the image to PNG')
      end
    end

    it 'reuses a successful ImageMagick probe across several previews in the same command' do
      gif_urls = %w[http://example.com/first.gif http://example.com/second.gif]
      with_converter("STDOUT.binmode; STDOUT.write(#{valid_png.dump})") do |_pid_file, version_calls_file|
        render_previews(gif_urls, [gif, gif])

        expect(File.read(version_calls_file)).to eq('1')
      end
    end

    it 'reuses the renderer detection across several previews in the same command' do
      allow(TerminalImage).to receive(:which).and_call_original

      render_previews(urls, [valid_png, valid_png])

      expect(TerminalImage).to have_received(:which).with('img2sixel').once
    end

    it 'discovers another available converter after the selected executable disappears' do
      gif_urls = %w[http://example.com/first.gif http://example.com/second.gif]
      with_converter('abort', remove_after_version: true) do
        Dir.mktmpdir do |dir|
          fallback = File.join(dir, 'convert')
          File.write(fallback, <<~RUBY)
            #!#{RbConfig.ruby}
            abort unless ARGV == ['-version'] || ARGV.last(2) == ['-[0]', 'png:-']
            if ARGV == ['-version']
              puts 'ImageMagick test converter'
              exit
            end
            abort unless STDIN.binmode.read == #{gif.dump}.b
            STDOUT.binmode
            STDOUT.write(#{valid_png.dump})
          RUBY
          File.chmod(0o755, fallback)
          allow(TerminalImage).to receive(:which).with('convert').and_return(fallback)

          warning = "warn: Could not preview #{gif_urls.first}: ImageMagick could not convert the image to PNG"
          render_previews(gif_urls, [gif, gif], warning:)
        end
      end
    end

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

    {
      'a palette exceeding the indexed bit depth' => [1, 'PLTE', "\0" * 9],
      'a palette with an incomplete entry' => [1, 'PLTE', "\0" * 4],
      'an empty palette' => [1, 'PLTE', ''],
      'transparency exceeding the palette size' => [2, 'tRNS', "\0" * 3]
    }.each do |description, (depth, type, content)|
      it "rejects #{description} before decoding and renders the next preview" do
        indexed = ChunkyPNG::Image.new(2, 1, ChunkyPNG::Color::TRANSPARENT)
        indexed[1, 0] = image[0, 0]
        datastream = indexed.to_datastream(color_mode: ChunkyPNG::COLOR_INDEXED, bit_depth: depth)
        if type == 'PLTE'
          datastream.palette_chunk = ChunkyPNG::Chunk::Palette.new(type, content)
        else
          datastream.transparency_chunk = ChunkyPNG::Chunk::Transparency.new(type, content)
        end

        expect(ChunkyPNG::Canvas).to receive(:from_datastream).once.and_call_original
        expect_preview_recovery(datastream.to_blob, 'Invalid PNG data')
      end
    end

    it 'accepts a suggested palette and a transparent color in a truecolor PNG' do
      datastream = image.to_datastream(:fast_rgb)
      datastream.palette_chunk = ChunkyPNG::Chunk::Palette.new('PLTE', "\0" * 768)
      datastream.transparency_chunk = ChunkyPNG::Chunk::Transparency.new('tRNS', [0, 0, 0].pack('n*'))

      expect { Irasutoya::Cli::Preview.show(StringIO.new(datastream.to_blob)) }
        .to output(/\e\[38;2;12;34;56m/).to_stdout
    end

    it 'accepts a two-byte transparent sample in a grayscale PNG' do
      grayscale = ChunkyPNG::Image.new(1, 1, ChunkyPNG::Color.grayscale(12))
      datastream = grayscale.to_datastream(color_mode: ChunkyPNG::COLOR_GRAYSCALE)
      datastream.transparency_chunk = ChunkyPNG::Chunk::Transparency.new('tRNS', [12].pack('n'))

      expect(Irasutoya::Cli::PreviewPNG.new.decode(StringIO.new(datastream.to_blob))[0, 0])
        .to eq(ChunkyPNG::Color::TRANSPARENT)
    end

    it 'rejects a palette in a grayscale PNG' do
      grayscale = ChunkyPNG::Image.new(1, 1, ChunkyPNG::Color.grayscale(12))
      datastream = grayscale.to_datastream(color_mode: ChunkyPNG::COLOR_GRAYSCALE)
      datastream.palette_chunk = ChunkyPNG::Chunk::Palette.new('PLTE', "\0" * 3)

      expect { Irasutoya::Cli::Preview.show(StringIO.new(datastream.to_blob)) }
        .to raise_error(TerminalImage::UnsupportedFormat, 'Invalid PNG data')
    end

    it 'rejects a transparency chunk in a PNG with an alpha channel' do
      datastream = image.to_datastream(:fast_rgba)
      datastream.transparency_chunk = ChunkyPNG::Chunk::Transparency.new('tRNS', "\0" * 6)

      expect { Irasutoya::Cli::Preview.show(StringIO.new(datastream.to_blob)) }
        .to raise_error(TerminalImage::UnsupportedFormat, 'Invalid PNG data')
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

    def with_converter(code, remove_after_version: false)
      Dir.mktmpdir do |dir|
        converter = File.join(dir, 'magick')
        pid_file = File.join(dir, 'converter.pid')
        version_calls_file = File.join(dir, 'version_calls')
        File.write(converter, <<~RUBY)
          #!#{RbConfig.ruby}
          abort unless ARGV == ['-version'] || ARGV.last(2) == ['-[0]', 'png:-']
          if ARGV == ['-version']
            calls = File.exist?(#{version_calls_file.dump}) ? Integer(File.read(#{version_calls_file.dump})) : 0
            File.write(#{version_calls_file.dump}, calls + 1)
            puts 'ImageMagick test converter'
            File.unlink(__FILE__) if #{remove_after_version}
            exit
          end
          abort unless STDIN.binmode.read == #{gif.dump}.b
          File.write(#{pid_file.dump}, Process.pid)
          #{code}
        RUBY
        File.chmod(0o755, converter)
        allow(TerminalImage).to receive(:which).and_call_original
        allow(TerminalImage).to receive(:which).with('magick').and_return(converter)
        yield pid_file, version_calls_file
      end
    end

    def expect_reaped(pid_file)
      pid = Integer(File.read(pid_file))
      expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
      expect { Process.waitpid(pid, Process::WNOHANG) }.to raise_error(Errno::ECHILD)
    end

    def expect_preview_recovery(rejected_image, message = 'PNG decompression exceeds the preview limit')
      render_previews(urls, [rejected_image, valid_png], warning: "warn: Could not preview #{urls.first}: #{message}")
    end

    def render_previews(urls, images, warning: nil)
      result = Irasutoya::Irasuto.new(url: 'http://example.com/', title: 'Preview', description: '', image_urls: urls)
      allow(Irasutoya::Cli::Illustration).to receive(:random).and_return(result)
      http = instance_double(Net::HTTP)
      expect(Net::HTTP).to receive(:start).with('example.com', 443, use_ssl: true, max_retries: 0,
                                              ignore_eof: false).once.and_return(http)
      expect(http).to receive(:finish).once
      urls.zip(images).each do |url, data|
        response = Net::HTTPOK.new('1.1', '200', 'OK')
        allow(response).to receive(:read_body).and_yield(data)
        allow(http).to receive(:request_get).with(URI.parse(url).request_uri, 'Accept-Encoding' => 'identity')
                                            .and_yield(response)
      end

      runner = Irasutoya::Cli::Runner.new([], {}, shell: Thor::Shell::Basic.new)
      allow(runner).to receive(:say).and_call_original
      expect(runner).to receive(:say).with(/\Awarn:/, :yellow).once.and_call_original if warning
      pixel = '\e\[38;2;12;34;56m'
      pattern = warning ? /#{Regexp.escape(warning)}\n#{pixel}/ : /#{pixel}.*\n.*#{pixel}/m
      expect do
        allow($stdout).to receive(:tty?).and_return(true)
        runner.random
      end.to output(pattern).to_stdout
    end
  end
end
