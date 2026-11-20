# frozen_string_literal: true

require 'fileutils'
require 'irasutoya'
require 'nokogiri'
require 'stringio'
require 'terminal_image'
require 'tmpdir'

RSpec.describe 'irasutoya download' do
  let(:page_url) { 'https://www.irasutoya.com/2026/01/cat.html' }
  let(:image_urls) { %w[https://example.com/cat.png https://example.com/other/cat.png?size=large] }
  let(:image_data) { ["\x89PNG".b, "\xFF\xFE".b] }
  let(:directory) { File.join(@workspace, 'nested', 'images') }

  around do |example|
    Dir.mktmpdir do |workspace|
      @workspace = workspace
      example.run
    end
  end

  before do
    images = image_urls.map { |url| %(<img src="#{url}">) }.join
    page = Nokogiri::HTML("<div class='entry'>#{images}</div>")
    link = Irasutoya::IrasutoLink.new(title: nil, show_url: page_url)
    allow(Irasutoya::IrasutoLink).to receive(:new).with(title: nil, show_url: page_url).and_return(link)
    allow(link).to receive(:fetch_page_and_parse).with(page_url).and_return(page)
    allow(URI).to receive(:parse).and_call_original
    image_urls.zip(image_data).each do |url, data|
      uri = URI.parse(url)
      allow(URI).to receive(:parse).with(url).and_return(uri)
      stub_image_response(uri, data, url == image_urls.first ? { 'content-length' => data.bytesize.to_s } : {})
    end
  end

  it 'saves every image, reports the paths, and skips the preview renderer' do
    allow($stdout).to receive(:tty?).and_return(true)
    expect(TerminalImage).not_to receive(:show)
    paths = %w[cat.png cat-1.png].map { |name| File.join(directory, name) }

    expect { run_download }.to output(paths.map { |path| "Saved: #{path}\n" }.join).to_stdout
    expect(paths.map { |path| File.binread(path) }).to eq(image_data)
    expect(Dir.children(directory)).to match_array(%w[cat.png cat-1.png])
  end

  it 'preserves existing files and skips occupied suffixes' do
    FileUtils.mkdir_p(directory)
    File.binwrite(File.join(directory, 'cat.png'), 'original')
    File.binwrite(File.join(directory, 'cat-1.png'), 'also original')

    expect { run_download }.to output(/cat-2\.png\n.*cat-3\.png\n/m).to_stdout
    paths = %w[cat.png cat-1.png cat-2.png cat-3.png].map { |name| File.join(directory, name) }
    expect(paths.map { |path| File.binread(path) }).to eq(['original', 'also original', *image_data])
  end

  it 'keeps completed images and removes the temporary file when a download fails' do
    allow(URI.parse(image_urls.last)).to receive(:open).and_raise(IOError, 'download failed')

    expect { run_download }.to raise_error(IOError, 'download failed')
    expect(Dir.children(directory)).to eq(['cat.png'])
  end

  it 'reports a truncated image URL and only announces and keeps the completed image' do
    stub_image_response(URI.parse(image_urls.last), 'short', { 'content-length' => '12' })

    expect do
      expect do
        expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Incomplete image download from #{image_urls.last}: expected 12 bytes, received 5\n").to_stderr
    end.to output("Saved: #{File.join(directory, 'cat.png')}\n").to_stdout
    expect(Dir.children(directory)).to eq(['cat.png'])
  end

  ['https://example.com/cat.html', 'https://www.irasutoya.com/cat photo.html'].each do |url|
    it "rejects #{url.inspect} before fetching the page or creating the output directory" do
      expect(Irasutoya::IrasutoLink).not_to receive(:new)

      expect do
        expect { run_download(url) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(
        /\AProvide an Irasutoya illustration page URL printed by search or random\.\n/
      ).to_stderr
      expect(File.exist?(directory)).to be(false)
    end
  end

  [['--output', ''], ['--output=']].each do |output_args|
    it "rejects #{output_args.map(&:inspect).join(' ')} before fetching the page" do
      expect(Irasutoya::IrasutoLink).not_to receive(:new)

      expect do
        expect do
          Irasutoya::Cli::Runner.start(['download', page_url, *output_args])
        end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Provide an output directory with --output.\n").to_stderr
    end
  end

  def run_download(url = page_url)
    Irasutoya::Cli::Runner.start(['download', url, '--output', directory])
  end

  def stub_image_response(uri, data, headers)
    source = StringIO.new(data)
    OpenURI::Meta.init(source)
    headers.each { |name, value| source.meta_add_field(name, value) }
    allow(uri).to receive(:open).and_yield(source)
  end
end
