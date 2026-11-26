# frozen_string_literal: true

require 'irasutoya/cli/preview'
require 'rbconfig'
require 'tempfile'
require 'tmpdir'

RSpec.describe 'Sixel image previews' do
  let(:png) { ChunkyPNG::Image.new(1, 1, ChunkyPNG::Color.rgb(12, 34, 56)).to_blob }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('TERM_PROGRAM', nil).and_return(nil)
    allow(TerminalImage).to receive(:which).and_call_original
  end

  it 'renders sixel output over standard input when TMPDIR contains a space' do
    with_img2sixel('STDOUT.binmode; STDOUT.write("sixel:#{STDIN.binmode.read.bytesize}")') do
      with_preview_file(png) do |file|
        expect { Irasutoya::Cli::Preview.show(file) }.to output("sixel:#{png.bytesize}\n").to_stdout
      end
    end
  end

  it 'raises a renderer error instead of printing a blank preview when img2sixel fails' do
    with_img2sixel('exit 1') do
      with_preview_file(png) do |file|
        expect { Irasutoya::Cli::Preview.show(file) }
          .to raise_error(TerminalImage::UnsupportedTerminal, 'img2sixel could not render the preview')
      end
    end
  end

  def with_img2sixel(code)
    Dir.mktmpdir do |dir|
      script = File.join(dir, 'img2sixel')
      File.write(script, "#!#{RbConfig.ruby}\n#{code}\n")
      File.chmod(0o755, script)
      allow(TerminalImage).to receive(:which).with('img2sixel').and_return(script)
      yield
    end
  end

  def with_preview_file(data)
    Dir.mktmpdir('irasutoya preview') do |tmpdir_with_space|
      Tempfile.create('', tmpdir_with_space, binmode: true) do |file|
        file.write(data)
        file.rewind
        yield file
      end
    end
  end
end
