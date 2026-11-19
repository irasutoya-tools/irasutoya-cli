# frozen_string_literal: true

require 'fileutils'
require 'irasutoya'
require 'nokogiri'
require 'net/http'
require 'socket'
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
    stub_images
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

  it 'follows a relative redirect without saving its body' do
    redirect = Net::HTTPFound.new('1.1', '302', 'Found')
    redirect['location'] = '/redirected.png'
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:read_body).and_yield(image_data.first)
    allow(@http).to receive(:request_get).with('/cat.png', 'Accept-Encoding' => 'identity').and_yield(redirect)
    allow(@http).to receive(:request_get).with('/redirected.png', 'Accept-Encoding' => 'identity').and_yield(response)
    expect(redirect).not_to receive(:read_body)

    expect { run_download }.to output(/cat\.png\n.*cat-1\.png\n/m).to_stdout
    expect(File.binread(File.join(directory, 'cat.png'))).to eq(image_data.first)
  end

  it 'follows up to 64 redirects' do
    stub_redirect_chain(64)

    expect { run_download }.to output(/cat\.png\n.*cat-1\.png\n/m).to_stdout
    expect(File.binread(File.join(directory, 'cat.png'))).to eq(image_data.first)
  end

  it 'rejects a 65th redirect and removes the temporary file' do
    stub_redirect_chain(65)

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Too many image download redirects\n").to_stderr
    expect(Dir.children(directory)).to be_empty
  end

  it 'reports a truncated image URL and only announces and keeps the completed image' do
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response['content-length'] = '12'
    allow(response).to receive(:read_body) do |&write_chunk|
      write_chunk.call('short')
      raise EOFError, 'end of file reached'
    end
    allow(@http).to receive(:request_get)
      .with('/other/cat.png?size=large', 'Accept-Encoding' => 'identity').and_yield(response)

    expect do
      expect do
        expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Incomplete image download from #{image_urls.last}: expected 12 bytes, received 5\n").to_stderr
    end.to output("Saved: #{File.join(directory, 'cat.png')}\n").to_stdout
    expect(Dir.children(directory)).to eq(['cat.png'])
  end

  it 'keeps completed images and removes the temporary file when a download fails' do
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:read_body) do |&write_chunk|
      write_chunk.call('partial')
      raise IOError, 'download failed'
    end
    allow(@http).to receive(:request_get).with('/other/cat.png?size=large', 'Accept-Encoding' => 'identity').and_yield(response)

    expect do
      expect { run_download }.to raise_error(IOError, 'download failed')
    end.to output("Saved: #{File.join(directory, 'cat.png')}\n").to_stdout
    expect(Dir.children(directory)).to eq(['cat.png'])
  end

  context 'with an HTTP server' do
    let(:image_urls) { ["http://127.0.0.1:#{@server.addr[1]}/cat.png"] }
    let(:payload) { (0..255).to_a.pack('C*') * 4096 }

    around do |example|
      TCPServer.open('127.0.0.1', 0) do |server|
        @server = server
        example.run
      end
    end

    def stub_images; end

    it 'streams a large response into a single temporary payload file' do
      path = File.join(directory, 'cat.png')
      expect(Tempfile).to receive(:create).once.with('.irasutoya-', directory, binmode: true).and_call_original

      serve_image(payload, payload.bytesize) do
        expect { run_download }.to output("Saved: #{path}\n").to_stdout
      end
      expect(File.binread(path)).to eq(payload)
      expect(Dir.children(directory)).to eq(['cat.png'])
    end

    it 'removes the temporary file when the response ends before its declared length' do
      serve_image(payload.byteslice(0, 16 * 1024), payload.bytesize) do
        expect do
          expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Incomplete image download from #{image_urls.first}: " \
                      "expected #{payload.bytesize} bytes, received 16384\n").to_stderr
      end
      expect(Dir.children(directory)).to be_empty
    end

    def serve_image(body, length)
      worker = Thread.new do
        socket = @server.accept
        socket.each_line { |line| break if line == "\r\n" }
        socket.write("HTTP/1.1 200 OK\r\nContent-Length: #{length}\r\nConnection: close\r\n\r\n", body)
      ensure
        socket&.close
      end
      yield
      worker.value
    ensure
      worker&.kill&.join
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

  def run_download(url = page_url)
    Irasutoya::Cli::Runner.start(['download', url, '--output', directory])
  end

  def stub_redirect_chain(count)
    paths = ['/cat.png', *(1..count).map { |step| "/redirect-#{step}.png" }]
    paths.each_cons(2) do |path, location|
      redirect = Net::HTTPFound.new('1.1', '302', 'Found')
      redirect['location'] = location
      allow(@http).to receive(:request_get).with(path, 'Accept-Encoding' => 'identity').and_yield(redirect)
    end
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:read_body).and_yield(image_data.first)
    allow(@http).to receive(:request_get).with(paths.last, 'Accept-Encoding' => 'identity').and_yield(response)
  end

  def stub_images
    @http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start)
      .with('example.com', 443, use_ssl: true, max_retries: 0, ignore_eof: false).and_yield(@http)
    image_urls.zip(image_data).each do |url, data|
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:read_body).and_yield(data)
      allow(@http).to receive(:request_get).with(URI.parse(url).request_uri, 'Accept-Encoding' => 'identity').and_yield(response)
    end
  end
end
