# frozen_string_literal: true

require 'fileutils'
require 'irasutoya'
require 'irasutoya/cli/download'
require 'nokogiri'
require 'irasutoya/cli/preview'
require 'stringio'
require 'tmpdir'

RSpec.describe 'irasutoya download' do
  let(:page_url) { 'https://www.irasutoya.com/2026/01/cat.html' }
  let(:image_urls) { %w[https://example.com/cat.png https://example.com/other/cat.png?size=large] }
  let(:image_data) { ["\x89PNG".b, "\xFF\xFE".b] }
  let(:directory) { File.join(@workspace, 'nested', 'images') }
  let(:link) do
    Irasutoya::IrasutoLink.new(title: nil, show_url: page_url).extend(Irasutoya::Cli::HtmlPage)
  end
  let(:http) { instance_double(Net::HTTP, finish: nil) }
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
    allow(Irasutoya::IrasutoLink).to receive(:new).with(title: nil, show_url: page_url).and_return(link)
    allow(link).to receive(:fetch_page_and_parse).with(page_url).and_return(page)
    allow(Net::HTTP).to receive(:start).with('example.com', 443, use_ssl: true, max_retries: 0,
                                           ignore_eof: false).and_return(http)
    image_urls.zip(image_data).each do |url, data|
      next unless data

      response = stub_image(url, data)
      response['content-length'] = data.bytesize.to_s if url == image_urls.first
    end
  end

  it 'saves the images from the illustration HTML in order without rendering previews' do
    allow(Irasutoya::IrasutoLink).to receive(:new).with(title: nil, show_url: page_url).and_call_original
    page_http = instance_double(Net::HTTP)
    expect(Net::HTTP).to receive(:start).with('www.irasutoya.com', 443, use_ssl: true, max_retries: 0,
                                              ignore_eof: false).once.and_yield(page_http)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response['content-type'] = 'text/html; charset=UTF-8'
    allow(response).to receive(:read_body).and_yield(<<~HTML)
      <img src="https://example.com/banner.png">
      <div class="entry">
        <img src="//example.com/cat.png">
        <img src="https://example.com/other/cat.png?size=large">
      </div>
    HTML
    expect(page_http).to receive(:request_get).with(URI(page_url).request_uri, request_headers).and_yield(response)

    allow($stdout).to receive(:tty?).and_return(true)
    expect(Irasutoya::Cli::Preview).not_to receive(:show)
    expect(Net::HTTP).to receive(:start).with('example.com', 443, use_ssl: true, max_retries: 0,
                                              ignore_eof: false).once.and_return(http)
    image_urls.each do |url|
      expect(http).to receive(:request_get).with(URI.parse(url).request_uri, request_headers).ordered
    end
    expect(http).to receive(:finish).once.ordered
    paths = %w[cat.png cat-1.png].map { |name| File.join(directory, name) }

    expect { run_download }.to output(paths.map { |path| "Saved: #{path}\n" }.join).to_stdout.and output('').to_stderr
    expect(paths.map { |path| File.binread(path) }).to eq(image_data)
    expect(Dir.children(directory)).to match_array(%w[cat.png cat-1.png])
  end

  it 'upgrades an HTTP page URL before passing it to the scraper' do
    expect { run_download(page_url.sub('https:', 'http:')) }.to output(/Saved: .*cat\.png/).to_stdout
  end

  it 'reports an existing output file once and exits before opening an image connection' do
    FileUtils.mkdir_p(File.dirname(directory))
    File.write(directory, 'original')
    expect(Net::HTTP).not_to receive(:start)

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/\ACould not create output directory #{Regexp.escape(directory)}: File exists[^\n]*\n\z/).to_stderr
      .and output('').to_stdout
    expect(File.read(directory)).to eq('original')
  end

  context 'with a legacy HTTP image URL' do
    let(:image_urls) { ['http://example.com/cat.png'] }

    it 'opens the HTTPS image URL and saves its contents' do
      expect(http).to receive(:request_get).with('/cat.png', request_headers)

      expect { run_download }.to output(/Saved: .*cat\.png/).to_stdout
      expect(File.binread(File.join(directory, 'cat.png'))).to eq(image_data.first)
    end
  end

  context 'with a non-HTTPS image URL that cannot be upgraded' do
    let(:image_urls) { ['ftp://example.com/cat.png'] }
    let(:image_data) { [] }

    it 'rejects the image before opening its URL' do
      expect(Net::HTTP).not_to receive(:start)

      expect do
        expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Could not download #{image_urls.first}: URL must use HTTPS\n").to_stderr
      expect(Dir.children(directory)).to be_empty
    end
  end

  it 'rejects an HTTP redirect from the page before contacting the destination' do
    allow(link).to receive(:fetch_page_and_parse).and_call_original
    page_http = instance_double(Net::HTTP)
    expect(Net::HTTP).to receive(:start).with('www.irasutoya.com', 443, use_ssl: true, max_retries: 0,
                                              ignore_eof: false).once.and_yield(page_http)
    redirect = Net::HTTPFound.new('1.1', '302', 'Found')
    redirect['location'] = 'http://other.example.com/resource'
    expect(page_http).to receive(:request_get).with(URI(page_url).request_uri, request_headers).and_yield(redirect)

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/Invalid HTTPS redirect for HTML page/).to_stderr
  end

  context 'with an image URL containing terminal control characters' do
    let(:image_urls) { ["https://example.com/cat\e[0m\n.png"] }
    let(:image_data) { [] }

    it 'escapes control characters in the download error sent to stderr' do
      expect(Net::HTTP).not_to receive(:start)

      expect do
        expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/\ACould not download https:\/\/example\.com\/cat\\x1B\[0m\\x0A\.png: [^\p{Cc}]+\n\z/).to_stderr
    end
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
    stub_const('Irasutoya::Cli::ImageTransfer::MAX_IMAGE_BYTES', image_data.first.bytesize)
    FileUtils.mkdir_p(directory)
    File.binwrite(File.join(directory, 'cat.png'), 'original')
    File.binwrite(File.join(directory, 'cat-1.png'), 'also original')

    expect { run_download }.to output(/cat-2\.png\n.*cat-3\.png\n/m).to_stdout
    paths = %w[cat.png cat-1.png cat-2.png cat-3.png].map { |name| File.join(directory, name) }
    expect(paths.map { |path| File.binread(path) }).to eq(['original', 'also original', *image_data])
  end

  it 'keeps completed images and removes the temporary file when a download fails' do
    expect(Net::HTTP).to receive(:start).once.and_return(http)
    response = stub_image(image_urls.last, image_data.last)
    allow(response).to receive(:read_body) do |&receive_chunk|
      receive_chunk.call('partial')
      expect(Dir.children(directory).grep(/\.png$/)).to eq(['cat.png'])
      expect(http).not_to have_received(:finish)
      raise IOError, 'download failed'
    end

    expect { run_download }.to raise_error(IOError, 'download failed')
    expect(http).to have_received(:finish).once
    expect(Dir.children(directory)).to eq(['cat.png'])
    expect(File.binread(File.join(directory, 'cat.png'))).to eq(image_data.first)
  end

  it 'exits on the transfer deadline and keeps only the completed image' do
    stub_const('Irasutoya::Cli::ImageTransfer::TRANSFER_TIMEOUT', 0.25)
    response = stub_image(image_urls.last, image_data.last)
    allow(response).to receive(:read_body) do |&receive_chunk|
      receive_chunk.call('partial')
      sleep 1
    end
    path = File.join(directory, 'cat.png')

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not fetch image #{image_urls.last}: Image transfer deadline exceeded\n").to_stderr
      .and output("Saved: #{path}\n").to_stdout
    expect(Dir.children(directory)).to eq(['cat.png'])
    expect(File.binread(path)).to eq(image_data.first)
  end

  it 'reports an image HTTP failure once and only announces and keeps the completed image' do
    response = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
    allow(http).to receive(:request_get).with(URI.parse(image_urls.last).request_uri, request_headers)
                                       .and_yield(response)
    path = File.join(directory, 'cat.png')
    stub_const('ARGV', ['download', page_url, '--output', directory])
    executable = File.expand_path('../../exe/irasutoya', __dir__)

    expect do
      expect { load executable }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not fetch image #{image_urls.last}: 404 \"Not Found\"\n").to_stderr
      .and output("Saved: #{path}\n").to_stdout
    expect(Dir.children(directory)).to eq(['cat.png'])
    expect(File.binread(path)).to eq(image_data.first)
  end

  it 'reports a connection closed before headers and only announces and keeps the completed image' do
    allow(http).to receive(:request_get).with(URI.parse(image_urls.last).request_uri, request_headers) do
      Net::HTTPResponse.read_new(Net::BufferedIO.new(StringIO.new('')))
    end
    path = File.join(directory, 'cat.png')
    stub_const('ARGV', ['download', page_url, '--output', directory])
    executable = File.expand_path('../../exe/irasutoya', __dir__)

    expect do
      expect { load executable }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not fetch image #{image_urls.last}: end of file reached\n").to_stderr
      .and output("Saved: #{path}\n").to_stdout
    expect(Dir.children(directory)).to eq(['cat.png'])
    expect(File.binread(path)).to eq(image_data.first)
  end

  it 'stops reading an oversized response without Content-Length and removes its temporary file' do
    stub_const('Irasutoya::Cli::ImageTransfer::MAX_IMAGE_BYTES', image_data.first.bytesize)
    expect(Net::HTTP).to receive(:start).once.and_return(http)
    response = stub_image(image_urls.last, image_data.last)
    allow(response).to receive(:read_body) do |&receive_chunk|
      receive_chunk.call(image_data.first)
      receive_chunk.call('x')
      raise 'Read past the download limit'
    end

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Image download exceeds the #{image_data.first.bytesize}-byte limit\n").to_stderr
    expect(http).to have_received(:finish).once
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
    expect(Net::HTTP).not_to receive(:start).with('example.com', 80, any_args)
    allow(http).to receive(:request_get).with('/cat.png', request_headers).and_yield(redirect)

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Image download redirect must use HTTPS\n").to_stderr
    expect(Dir.children(directory)).to be_empty
  end

  it 'rejects a redirect to a non-HTTP destination before starting another request' do
    allow(http).to receive(:request_get).with('/cat.png', request_headers)
                                       .and_yield(redirect_to('file:///cat.png'))
    expect(Net::HTTP).to receive(:start).once.and_return(http)
    images = Nokogiri::HTML('<div class="entry"><img src="http://example.com/cat.png"></div>')
    allow(link).to receive(:fetch_page_and_parse).with(page_url).and_return(images)

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Image download redirect must use HTTPS\n").to_stderr
    expect(Dir.children(directory)).to be_empty
  end

  it 'stops following redirects at the download limit and removes the temporary file' do
    paths = ['/cat.png', *(1..6).map { |index| "/#{index}.png" }]
    paths.each_cons(2) do |source, target|
      expect(http).to receive(:request_get).with(source, request_headers).ordered.and_yield(redirect_to(target))
    end

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Too many image download redirects\n").to_stderr
    expect(Dir.children(directory)).to be_empty
  end

  it 'reports an unsupported hard link and keeps only the completed image' do
    saved_path = File.join(directory, 'cat.png')
    failed_path = File.join(directory, 'cat-1.png')
    allow(File).to receive(:link).and_call_original
    allow(File).to receive(:link).with(anything, failed_path) do |source, _destination|
      expect(File.binread(source)).to eq(image_data.last)
      raise Errno::EOPNOTSUPP
    end

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not save image at #{failed_path}: #{Errno::EOPNOTSUPP.new.message}\n").to_stderr
      .and output("Saved: #{saved_path}\n").to_stdout
    expect(http).to have_received(:finish).once
    expect(Dir.children(directory)).to eq(['cat.png'])
    expect(File.binread(saved_path)).to eq(image_data.first)
  end

  it 'reports a temporary file creation failure before starting an image transfer' do
    allow(Tempfile).to receive(:create).with('.irasutoya-', directory, binmode: true).and_raise(Errno::EACCES)
    expect(Net::HTTP).not_to receive(:start)

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not create temporary image in #{directory}: #{Errno::EACCES.new.message}\n").to_stderr
      .and output('').to_stdout
    expect(Dir.children(directory)).to be_empty
  end

  it 'reports a temporary write failure and removes the temporary file' do
    FileUtils.mkdir_p(directory)
    file = Tempfile.create('.irasutoya-', directory, binmode: true)
    allow(Tempfile).to receive(:create).with('.irasutoya-', directory, binmode: true).and_return(file)
    allow(file).to receive(:write).and_raise(Errno::ENOSPC)

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not save image at #{file.path}: #{Errno::ENOSPC.new.message}\n").to_stderr
      .and output('').to_stdout
    expect(Dir.children(directory)).to be_empty
    expect(file).to be_closed
  end

  it 'reports a missing temporary source when it disappears before publication' do
    path = File.join(directory, 'cat.png')
    allow(File).to receive(:link).with(anything, path) do |source, _destination|
      File.unlink(source)
      raise Errno::ENOENT
    end

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not save image at #{path}: #{Errno::ENOENT.new.message}\n").to_stderr
      .and output('').to_stdout
    expect(Dir.children(directory)).to be_empty
  end

  ["204 No Content\r\n", "200 OK\r\nContent-Length: 0\r\n"].each do |headers|
    it "rejects an empty #{headers.lines.first.strip} response without saving or announcing the image" do
      allow(http).to receive(:request_get).with('/cat.png', request_headers) do |&read_response|
        socket = Net::BufferedIO.new(StringIO.new("HTTP/1.1 #{headers}\r\n"))
        response = Net::HTTPResponse.read_new(socket)
        response.reading_body(socket, true) { read_response.call(response) }
      end

      expect do
        expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Could not fetch image #{image_urls.first}: Empty image response\n").to_stderr
        .and output('').to_stdout
      expect(Dir.children(directory)).to be_empty
    end
  end

  it 'reports a truncated image URL and only announces and keeps the completed image' do
    allow(http).to receive(:request_get).with(URI.parse(image_urls.last).request_uri, request_headers) do |&read_response|
      wire = StringIO.new("HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\nshort")
      socket = Net::BufferedIO.new(wire)
      response = Net::HTTPResponse.read_new(socket)
      response.ignore_eof = false
      response.reading_body(socket, true) { read_response.call(response) }
    end

    expect do
      expect do
        expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Incomplete image download from #{image_urls.last}: expected 12 bytes, received 5\n").to_stderr
    end.to output("Saved: #{File.join(directory, 'cat.png')}\n").to_stdout
    expect(Dir.children(directory)).to eq(['cat.png'])
  end

  it 'reports a missing illustration page once and exits before creating the destination' do
    allow(link).to receive(:fetch_irasuto).and_raise(OpenURI::HTTPError.new('404 Not Found', nil))

    expect do
      expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not fetch illustration page #{page_url}: 404 Not Found\n").to_stderr
      .and output('').to_stdout
    expect(File.exist?(File.dirname(directory))).to be(false)
  end

  it 'rejects a complete partial response without saving or announcing the image' do
    response = Net::HTTPPartialContent.new('1.1', '206', 'Partial Content')
    response['content-length'] = '5'
    response['content-range'] = 'bytes 5-9/12'
    allow(http).to receive(:request_get).with(URI.parse(image_urls.first).request_uri, request_headers)
                                       .and_yield(response)
    expect(response).not_to receive(:read_body)

    expect do
      expect do
        expect { run_download }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Incomplete image download from #{image_urls.first}: HTTP 206 Partial Content\n").to_stderr
    end.to output('').to_stdout
    expect(Dir.children(directory)).to be_empty
  end

  it 'uses chunked framing when both Transfer-Encoding and Content-Length are present' do
    response = stub_image(image_urls.last, image_data.last)
    response['transfer-encoding'] = 'chunked'
    response['content-length'] = '12'

    expect { run_download }.to output(/cat\.png\n.*cat-1\.png\n/m).to_stdout
    expect(File.binread(File.join(directory, 'cat-1.png'))).to eq(image_data.last)
  end

  context 'when the filename exceeds the 255-byte component limit' do
    let(:filename) { "#{'a' * 252}.png" }
    let(:image_urls) { ["https://example.com/#{filename}"] }

    it 'shortens the first filename and preserves that file on a second download' do
      first_path = File.join(directory, "#{'a' * 251}.png")
      second_path = File.join(directory, "#{'a' * 249}-1.png")

      expect { run_download }.to output("Saved: #{first_path}\n").to_stdout
      expect(File.binread(first_path)).to eq(image_data.first)

      stub_image(image_urls.first, image_data.last)
      expect { run_download }.to output("Saved: #{second_path}\n").to_stdout
      expect([first_path, second_path].map { |path| File.binread(path) }).to eq(image_data)
      expect(Dir.children(directory)).to match_array([File.basename(first_path), File.basename(second_path)])
    end
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

  def redirect_to(location)
    Net::HTTPFound.new('1.1', '302', 'Found').tap { |response| response['location'] = location }
  end
end
