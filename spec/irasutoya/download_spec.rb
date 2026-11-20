# frozen_string_literal: true

require 'fileutils'
require 'irasutoya'
require 'nokogiri'
require 'terminal_image'
require 'tmpdir'

RSpec.describe 'irasutoya download' do
  let(:page_url) { 'https://www.irasutoya.com/2026/01/cat.html' }
  let(:image_urls) { %w[https://example.com/cat.png https://example.com/other/cat.png?size=large] }
  let(:image_data) { ["\x89PNG".b, "\xFF\xFE".b] }
  let(:transfer) { Irasutoya::Cli::ImageTransfer }
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
    image_urls.zip(image_data).each do |url, data|
      allow(transfer).to receive(:fetch).with(URI.parse(url)).and_yield(data)
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

  context 'with 100 images sharing a basename' do
    let(:image_urls) { Array.new(100) { |index| "https://example.com/#{index}/cat.png" } }
    let(:image_data) { Array.new(100) { |index| "image #{index}" } }

    it 'saves each image under a sequential name with one link attempt per image' do
      expect(File).to receive(:link).exactly(100).times.and_call_original
      names = ['cat.png', *(1...100).map { |index| "cat-#{index}.png" }]
      paths = names.map { |name| File.join(directory, name) }

      expect { run_download }.to output(paths.map { |path| "Saved: #{path}\n" }.join).to_stdout
      expect(paths.map { |path| File.binread(path) }).to eq(image_data)
      expect(Dir.children(directory)).to match_array(names)
    end
  end

  it 'retries when another writer claims the next suffix before the link' do
    collision = File.join(directory, 'cat-1.png')
    allow(File).to receive(:link).and_wrap_original do |link, source, path|
      File.binwrite(collision, 'another writer') if path == collision
      link.call(source, path)
    end
    paths = %w[cat.png cat-2.png].map { |name| File.join(directory, name) }

    expect { run_download }.to output(paths.map { |path| "Saved: #{path}\n" }.join).to_stdout
    expect(paths.map { |path| File.binread(path) }).to eq(image_data)
    expect(File.binread(collision)).to eq('another writer')
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
    allow(transfer).to receive(:fetch).with(URI.parse(image_urls.last)) do |&read_chunk|
      read_chunk.call('partial')
      expect(Dir.children(directory).grep(/\.png$/)).to eq(['cat.png'])
      raise IOError, 'download failed'
    end

    expect { run_download }.to raise_error(IOError, 'download failed')
    expect(Dir.children(directory)).to eq(['cat.png'])
  end

  it 'cannot save an image when the destination filesystem rejects hard links' do
    allow(File).to receive(:link).with(anything, File.join(directory, 'cat.png')) do |source, _destination|
      expect(File.binread(source)).to eq(image_data.first)
      raise Errno::EOPNOTSUPP
    end

    expect { run_download }.to raise_error(Errno::EOPNOTSUPP)
    expect(Dir.children(directory)).to be_empty
  end

  it 'reports a truncated image URL and only announces and keeps the completed image' do
    uri = URI.parse(image_urls.last)
    allow(transfer).to receive(:fetch).with(uri).and_call_original
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start).with(uri.hostname, uri.port, use_ssl: true, max_retries: 0).and_yield(http)
    allow(http).to receive(:request_get).with(uri.request_uri, 'Accept-Encoding' => 'identity') do |&read_response|
      wire = StringIO.new("HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\nshort")
      socket = Net::BufferedIO.new(wire)
      response = Net::HTTPResponse.read_new(socket)
      response.reading_body(socket, true) { read_response.call(response) }
    end

    expect do
      expect do
        expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Incomplete image download from #{image_urls.last}: expected 12 bytes, received 5\n").to_stderr
    end.to output("Saved: #{File.join(directory, 'cat.png')}\n").to_stdout
    expect(Dir.children(directory)).to eq(['cat.png'])
  end

  context 'when the illustration page contains no images' do
    let(:image_urls) { [] }

    it 'reports the page URL and exits with status 1 before creating the destination' do
      expect do
        expect do
          expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("No images found on #{page_url}\n").to_stderr
      end.to output('').to_stdout
      expect(File.exist?(directory)).to be(false)
    end
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
end
