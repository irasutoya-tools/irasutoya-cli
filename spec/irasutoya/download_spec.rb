# frozen_string_literal: true

require 'fileutils'
require 'irasutoya'
require 'irasutoya/cli/download'
require 'nokogiri'
require 'irasutoya/cli/preview'
require 'tmpdir'

RSpec.describe 'irasutoya download' do
  let(:page_url) { 'https://www.irasutoya.com/2026/01/cat.html' }
  let(:image_urls) { %w[https://example.com/cat.png https://example.com/other/cat.png?size=large] }
  let(:image_data) { ["\x89PNG".b, "\xFF\xFE".b] }
  let(:directory) { File.join(@workspace, 'nested', 'images') }
  let(:http) { instance_double(Net::HTTP) }
  let(:request_headers) { { 'Accept-Encoding' => 'identity' } }

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
    allow(Net::HTTP).to receive(:start).with('example.com', 443, use_ssl: true, max_retries: 0,
                                           ignore_eof: false).and_yield(http)
    image_urls.zip(image_data).each do |url, data|
      response = stub_image(url, data)
      response['content-length'] = data.bytesize.to_s if url == image_urls.first
    end
  end

  it 'saves every image, reports the paths, and skips the preview renderer' do
    allow($stdout).to receive(:tty?).and_return(true)
    expect(Irasutoya::Cli::Preview).not_to receive(:show)
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
    stub_const('Irasutoya::Cli::Download::MAX_IMAGE_BYTES', image_data.first.bytesize)
    FileUtils.mkdir_p(directory)
    File.binwrite(File.join(directory, 'cat.png'), 'original')
    File.binwrite(File.join(directory, 'cat-1.png'), 'also original')

    expect { run_download }.to output(/cat-2\.png\n.*cat-3\.png\n/m).to_stdout
    paths = %w[cat.png cat-1.png cat-2.png cat-3.png].map { |name| File.join(directory, name) }
    expect(paths.map { |path| File.binread(path) }).to eq(['original', 'also original', *image_data])
  end

  it 'keeps completed images and removes the temporary file when a download fails' do
    allow(http).to receive(:request_get).with(URI.parse(image_urls.last).request_uri, request_headers)
                                       .and_raise(IOError, 'download failed')

    expect { run_download }.to raise_error(IOError, 'download failed')
    expect(Dir.children(directory)).to eq(['cat.png'])
  end

  it 'stops reading an oversized response without Content-Length and removes its temporary file' do
    stub_const('Irasutoya::Cli::Download::MAX_IMAGE_BYTES', image_data.first.bytesize)
    response = stub_image(image_urls.last, image_data.last)
    allow(response).to receive(:read_body) do |&receive_chunk|
      receive_chunk.call(image_data.first)
      receive_chunk.call('x')
      raise 'Read past the download limit'
    end

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Image download exceeds the #{image_data.first.bytesize}-byte limit\n").to_stderr
    expect(Dir.children(directory)).to eq(['cat.png'])
    expect(File.binread(File.join(directory, 'cat.png'))).to eq(image_data.first)
  end

  it 'follows a relative redirect without reading its body' do
    redirect = Net::HTTPFound.new('1.1', '302', 'Found')
    redirect['location'] = '/redirected.png'
    expect(redirect).not_to receive(:read_body)
    allow(http).to receive(:request_get).with('/cat.png', request_headers).and_yield(redirect)
    stub_image('https://example.com/redirected.png', image_data.first)

    expect { run_download }.to output(/cat\.png\n.*cat-1\.png\n/m).to_stdout
    expect(File.binread(File.join(directory, 'cat.png'))).to eq(image_data.first)
  end

  it 'rejects an HTTPS redirect to HTTP and removes the temporary file' do
    redirect = Net::HTTPFound.new('1.1', '302', 'Found')
    redirect['location'] = 'http://example.com/redirected.png'
    allow(http).to receive(:request_get).with('/cat.png', request_headers).and_yield(redirect)

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Image download redirect must use HTTPS\n").to_stderr
    expect(Dir.children(directory)).to be_empty
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
    response = stub_image(image_urls.last, 'short')
    response['content-length'] = '12'

    expect do
      expect do
        expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Incomplete image download from #{image_urls.last}: expected 12 bytes, received 5\n").to_stderr
    end.to output("Saved: #{File.join(directory, 'cat.png')}\n").to_stdout
    expect(Dir.children(directory)).to eq(['cat.png'])
  end

  it 'uses chunked framing when both Transfer-Encoding and Content-Length are present' do
    response = stub_image(image_urls.last, image_data.last)
    response['transfer-encoding'] = 'chunked'
    response['content-length'] = '12'

    expect { run_download }.to output(/cat\.png\n.*cat-1\.png\n/m).to_stdout
    expect(File.binread(File.join(directory, 'cat-1.png'))).to eq(image_data.last)
  end

  context 'when the filename reaches the 255-byte component limit' do
    let(:filename) { "#{'a' * 251}.png" }
    let(:image_urls) { ["https://example.com/#{filename}", "https://example.com/other/#{filename}"] }

    it 'preserves the first image and shortens the stem to fit the suffix' do
      paths = [filename, "#{'a' * 249}-1.png"].map { |name| File.join(directory, name) }

      expect { run_download }.to output(paths.map { |path| "Saved: #{path}\n" }.join).to_stdout
      expect(paths.map { |path| File.binread(path) }).to eq(image_data)
      expect(Dir.children(directory)).to match_array(paths.map { |path| File.basename(path) })
    end

    it 'preserves occupied names and shortens the stem further for two-digit suffixes' do
      FileUtils.mkdir_p(directory)
      occupied_names = [filename, *(1..9).map { |index| "#{'a' * 249}-#{index}.png" }]
      occupied_paths = occupied_names.map { |name| File.join(directory, name) }
      occupied_paths.each { |path| File.binwrite(path, 'original') }
      paths = [10, 11].map { |index| File.join(directory, "#{'a' * 248}-#{index}.png") }

      expect { run_download }.to output(paths.map { |path| "Saved: #{path}\n" }.join).to_stdout
      expect(paths.map { |path| File.binread(path) }).to eq(image_data)
      expect(occupied_paths.map { |path| File.binread(path) }).to all(eq('original'))
    end
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

  def stub_image(url, data)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:read_body).and_yield(data)
    allow(http).to receive(:request_get).with(URI.parse(url).request_uri, request_headers).and_yield(response)
    response
  end
end
