# frozen_string_literal: true

require 'irasutoya/cli/illustration'
require 'irasutoya/cli/download'
require 'irasutoya/cli/preview'
require 'openssl'
require 'socket'
require 'tmpdir'

RSpec.describe Irasutoya::Cli::HtmlPage do
  let(:host) { 'www.irasutoya.com' }
  let(:page_url) { "https://#{host}/cat.html" }
  let(:http) { instance_double(Net::HTTP) }
  let(:headers) { { 'Accept-Encoding' => 'identity' } }
  let(:detail) { '<div class="entry"><img src="https://example.com/cat.png"></div>' }
  let(:search_html) { %(<div class="box"><a href="#{page_url}"></a><a>Cat</a></div>) }

  before do
    stub_const('Irasutoya::Cli::HtmlPage::MAX_BYTES', 256)
    allow(Net::HTTP).to receive(:start).with(host, 443, use_ssl: true, max_retries: 0,
                                           ignore_eof: false).and_yield(http)
  end

  it 'parses a response at the byte limit using its declared charset' do
    html = '<title>猫</title>'.encode('Shift_JIS').b.ljust(256)
    response = respond('/cat.html')
    response['content-type'] = 'text/html; charset="Shift_JIS"'
    response['content-length'] = '256'
    allow(response).to receive(:read_body).and_yield(html[0, 10]).and_yield(html[10..])

    document = Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url)
    expect(document.at_css('title').text).to eq('猫')
  end

  it 'rejects an oversized search response before reading or parsing it' do
    response = respond('/search?q=cat')
    response['content-length'] = '257'
    expect(response).not_to receive(:read_body)
    expect(Nokogiri::HTML).not_to receive(:parse)

    expect { Irasutoya::Cli::Runner.new.search('cat') }
      .to raise_error(Thor::Error, 'HTML response exceeds the 256-byte limit')
  end

  it 'skips an oversized detail without a declared length and displays the next result' do
    list = search_html + search_html.sub('/cat.html', '/next.html')
    allow(respond('/search?q=cat')).to receive(:read_body).and_yield(list)
    stream_oversized_detail
    allow(respond('/next.html')).to receive(:read_body).and_yield(detail)

    expect { Irasutoya::Cli::Runner.new.search('cat') }
      .to output(/Page URL:    https:\/\/www\.irasutoya\.com\/next\.html/).to_stdout
      .and output("warn: Could not fetch result page #{page_url}: HTML response exceeds the 256-byte limit\n").to_stderr
  end

  it 'reports an oversized download page before parsing or transferring images' do
    stream_oversized_detail
    expect(Nokogiri::HTML).not_to receive(:parse)
    expect(Irasutoya::Cli::ImageTransfer).not_to receive(:fetch)

    expect { Irasutoya::Cli::Download.new(page_url, 'unused').save }
      .to raise_error(Thor::Error, "Could not fetch illustration page #{page_url}: HTML response exceeds the 256-byte limit")
  end

  it 'reports an oversized random illustration page' do
    allow(Irasutoya::Cli::Illustration).to receive(:random_url).and_return(page_url)
    stream_oversized_detail

    expect { Irasutoya::Cli::Runner.new.random }
      .to raise_error(Thor::Error, 'HTML response exceeds the 256-byte limit')
  end

  it 'closes an oversized chunked stream even when the chunk terminator never arrives' do
    context = local_tls_context
    store = OpenSSL::X509::Store.new
    store.add_cert(context.cert)
    allow(Net::HTTP).to receive(:start).and_wrap_original do |start, host, port, **options, &request|
      start.call(host, port, nil, **options, cert_store: store, read_timeout: 1, &request)
    end

    TCPServer.open('127.0.0.1', 0) do |server|
      tls_server = OpenSSL::SSL::SSLServer.new(server, context)
      worker = Thread.new { serve_unterminated_chunk(tls_server) }
      url = "https://127.0.0.1:#{server.addr[1]}/cat.html"
      expect(Nokogiri::HTML).not_to receive(:parse)

      expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(url) }
        .to raise_error(described_class::Error, 'HTML response exceeds the 256-byte limit')
      expect(worker.join(5)).to eq(worker)
    ensure
      worker&.kill&.join
    end
  end

  it 'preserves an unrelated body read error' do
    allow(respond('/cat.html')).to receive(:read_body).and_raise(EOFError, 'end of file reached')
    expect(http).not_to receive(:finish)

    expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url) }
      .to raise_error(EOFError, 'end of file reached')
  end

  it 'does not read an error response body' do
    response = respond('/cat.html', Net::HTTPNotFound.new('1.1', '404', 'Not Found'))
    expect(response).not_to receive(:read_body)

    expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url) }
      .to raise_error(OpenURI::HTTPError, '404 Not Found')
  end

  it 'follows a relative redirect without reading its body' do
    redirect = respond('/cat.html', Net::HTTPFound.new('1.1', '302', 'Found'))
    redirect['location'] = 'next.html'
    expect(redirect).not_to receive(:read_body)
    allow(respond('/next.html')).to receive(:read_body).and_yield(detail)

    expect(Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url).at_css('img')['src'])
      .to eq('https://example.com/cat.png')
  end

  it 'lists, previews and saves relative images using the redirected detail page URL' do
    final_host = 'detail.example.com'
    final_path = '/2026/01/cat.html'
    redirect = respond('/cat.html', Net::HTTPFound.new('1.1', '302', 'Found'))
    redirect['location'] = "https://#{final_host}#{final_path}"
    page_http = instance_double(Net::HTTP)
    image_http = instance_double(Net::HTTP, finish: nil)
    http_options = { use_ssl: true, max_retries: 0, ignore_eof: false }
    allow(Net::HTTP).to receive(:start).with(final_host, 443, **http_options) do |*_, &request|
      request ? request.call(page_http) : image_http
    end
    page = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(page_http).to receive(:request_get).with(final_path, headers).and_yield(page)
    allow(page).to receive(:read_body).and_yield(
      '<div class="entry"><img src="/images/root.png"><img src="images/relative.png"></div>'
    )
    image_paths = %w[/images/root.png /2026/01/images/relative.png]
    image_paths.each do |path|
      image = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(image).to receive(:read_body).and_yield(path)
      expect(image_http).to receive(:request_get).with(path, headers).twice.and_yield(image)
    end

    allow(Irasutoya::Cli::Illustration).to receive(:random_url).and_return(page_url)
    previews = []
    allow(Irasutoya::Cli::Preview).to receive(:show) { |file| previews << file.read }
    image_lines = image_paths.map { |path| "Image URL:   https://#{final_host}#{path}\n" }.join
    expect do
      allow($stdout).to receive(:tty?).and_return(true)
      Irasutoya::Cli::Runner.new.random
    end.to output(/#{Regexp.escape(image_lines)}\z/).to_stdout
    expect(previews).to eq(image_paths)

    Dir.mktmpdir do |directory|
      saved = []
      Irasutoya::Cli::Download.new(page_url, directory).save { |path| saved << path }
      expect(saved.map { |path| File.binread(path) }).to eq(image_paths)
    end
  end

  it 'stops after the redirect limit' do
    redirect = respond('/cat.html', Net::HTTPFound.new('1.1', '302', 'Found'))
    redirect['location'] = '/cat.html'
    expect(http).to receive(:request_get).with('/cat.html', headers).exactly(6).times.and_yield(redirect)

    expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url) }
      .to raise_error(described_class::Error, 'Too many HTML redirects')
  end

  it 'rejects malformed redirect destinations' do
    redirect = respond('/cat.html', Net::HTTPFound.new('1.1', '302', 'Found'))
    redirect['location'] = 'http://['

    expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url) }
      .to raise_error(described_class::Error, 'Invalid HTTPS redirect for HTML page')
  end

  def respond(path, response = Net::HTTPOK.new('1.1', '200', 'OK'))
    allow(http).to receive(:request_get).with(path, headers).and_yield(response)
    response
  end

  def local_tls_context
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=127.0.0.1')
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 60
    cert.add_extension(OpenSSL::X509::ExtensionFactory.new.create_extension('subjectAltName', 'IP:127.0.0.1'))
    cert.sign(key, OpenSSL::Digest.new('SHA256'))

    OpenSSL::SSL::SSLContext.new.tap do |context|
      context.cert = cert
      context.key = key
    end
  end

  def serve_unterminated_chunk(server)
    socket = server.accept
    socket.each_line { |line| break if line == "\r\n" }
    socket.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n101\r\n" + ('a' * 257))
    socket.read
  ensure
    socket&.close
  end

  def stream_oversized_detail
    response = respond('/cat.html')
    response['transfer-encoding'] = 'chunked'
    expect(http).to receive(:finish)
    expect(response).to receive(:read_body) do |&receive_chunk|
      receive_chunk.call(detail.ljust(256))
      receive_chunk.call('猫')
      raise 'Read continued after the HTML limit was exceeded'
    end
  end
end
