# frozen_string_literal: true

require 'irasutoya/cli/illustration'
require 'irasutoya/cli/download'
require 'json'
require 'openssl'
require 'socket'

RSpec.describe Irasutoya::Cli::HtmlPage do
  let(:host) { 'www.irasutoya.com' }
  let(:page_url) { "https://#{host}/cat.html" }
  let(:http) { instance_double(Net::HTTP, started?: true, finish: nil) }
  let(:headers) { { 'Accept-Encoding' => 'identity' } }
  let(:detail) { '<div class="entry"><img src="https://example.com/cat.png"></div>' }
  let(:search_html) { %(<div class="box"><a href="#{page_url}"></a><a>Cat</a></div>) }

  before do
    stub_const('Irasutoya::Cli::HtmlPage::MAX_BYTES', 256)
    allow(Net::HTTP).to receive(:start).with(host, 443, use_ssl: true, max_retries: 0,
                                           ignore_eof: false) do |*, &request|
      allow(http).to receive(:started?).and_return(true)
      request ? request.call(http) : http
    end
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
    with_tls_server do |server, url|
      worker = Thread.new { serve_unterminated_chunk(server) }
      expect(Nokogiri::HTML).not_to receive(:parse)

      expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(url) }
        .to raise_error(described_class::Error, 'HTML response exceeds the 256-byte limit')
      expect(worker.join(5)).to eq(worker)
    ensure
      worker&.kill&.join
    end
  end

  it 'applies one deadline across redirects and a body that keeps making read progress' do
    stub_const('Irasutoya::Cli::HtmlPage::FETCH_TIMEOUT', 0.9)
    with_tls_server do |server, url|
      worker = Thread.new { serve_slow_redirect_and_body(server) }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(url) }
        .to raise_error(described_class::Error, 'HTML fetch deadline exceeded')
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1.2
    ensure
      worker&.kill&.join
    end
  end

  it 'closes the TCP connection when the TLS handshake exceeds the deadline' do
    stub_const('Irasutoya::Cli::HtmlPage::FETCH_TIMEOUT', 0.5)
    allow(Net::HTTP).to receive(:start).and_wrap_original do |start, host, port, **options, &request|
      start.call(host, port, nil, **options, &request)
    end

    TCPServer.open('127.0.0.1', 0) do |server|
      url = "https://127.0.0.1:#{server.addr[1]}/cat.html"
      worker = Thread.new do
        socket = server.accept
        socket.read
      ensure
        socket&.close
      end

      expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(url) }
        .to raise_error(described_class::Error, 'HTML fetch deadline exceeded')
      expect(worker.join(2)).to eq(worker)
      expect(worker.value).not_to be_empty
    ensure
      worker&.kill&.join
    end
  end

  context 'with persistent HTTPS search responses' do
    let(:context) { local_tls_context }

    before do
      stub_const('Irasutoya::Cli::HtmlPage::MAX_BYTES', 320)
      store = OpenSSL::X509::Store.new
      store.add_cert(context.cert)
      allow(Net::HTTP).to receive(:start).and_wrap_original do |start, host, port, **options|
        start.call(host, port, nil, **options, ipaddr: '127.0.0.1', cert_store: store, read_timeout: 2)
      end
    end

    it 'fetches the search page and all three details on one connection and emits results in order' do
      serve_html(context, [%w[/search?q=cat /first.html /second.html /third.html]]) do |origin|
        urls = %w[first second third].map { |name| "#{origin}/#{name}.html" }
        route_search_to(origin)

        expect { run_search }
          .to output(satisfy { |stdout| result_urls(stdout) == urls }).to_stdout.and output('').to_stderr
      end
    end

    it 'uses a separate connection for a different origin and returns to the original connection' do
      serve_html(context, [['/second.html']]) do |other_origin|
        serve_html(context, [%w[/search?q=cat /first.html /third.html]], other_origin:) do |origin|
          route_search_to(origin)
          urls = ["#{origin}/first.html", "#{other_origin}/second.html", "#{origin}/third.html"]

          expect { run_search }
            .to output(satisfy { |stdout| result_urls(stdout) == urls }).to_stdout.and output('').to_stderr
        end
      end
    end

    it 'discards a timed-out connection, warns, and fetches the next detail' do
      stub_const('Irasutoya::Cli::HtmlPage::FETCH_TIMEOUT', 0.5)
      serve_html(context, [%w[/search?q=cat /first.html /second.html], ['/third.html']], stalled: '/second.html') do |origin|
        route_search_to(origin)
        urls = ["#{origin}/first.html", "#{origin}/third.html"]

        expect { run_search }
          .to output(satisfy { |stdout| result_urls(stdout) == urls }).to_stdout
          .and output("warn: Could not fetch result page #{origin}/second.html: HTML fetch deadline exceeded\n")
          .to_stderr
      end
    end

    it 'discards the connection after aborting an oversized chunked response and fetches the next detail' do
      serve_html(context, [%w[/search?q=cat /first.html /second.html], ['/third.html']], oversized: '/second.html') do |origin|
        route_search_to(origin)
        urls = ["#{origin}/first.html", "#{origin}/third.html"]

        expect { run_search }
          .to output(satisfy { |stdout| result_urls(stdout) == urls }).to_stdout
          .and output("warn: Could not fetch result page #{origin}/second.html: HTML response exceeds the 320-byte limit\n")
          .to_stderr
      end
    end

    it 'warns once for a truncated detail body and fetches the next detail on a new connection' do
      serve_html(context, [%w[/search?q=cat /first.html /second.html], ['/third.html']], truncated: '/second.html') do |origin|
        route_search_to(origin)
        urls = ["#{origin}/first.html", "#{origin}/third.html"]
        failed_url = "#{origin}/second.html"
        warning = "warn: Could not fetch result page #{failed_url}: Incomplete HTML response from #{failed_url}\n"

        expect { run_search }
          .to output(satisfy { |stdout| result_urls(stdout) == urls }).to_stdout.and output(warning).to_stderr
      end
    end
  end

  it 'preserves an unrelated body read error' do
    allow(respond('/cat.html')).to receive(:read_body).and_raise(IOError, 'body read failed')
    expect(http).not_to receive(:finish)

    expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url) }
      .to raise_error(IOError, 'body read failed')
  end

  it 'includes the redirected URL when the connection closes before the response headers' do
    redirect = respond('/cat.html', Net::HTTPFound.new('1.1', '302', 'Found'))
    redirect['location'] = '/next.html'
    allow(http).to receive(:request_get).with('/next.html', headers).and_raise(EOFError)

    expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url) }
      .to raise_error(described_class::Error, "Incomplete HTML response from https://#{host}/next.html")
  end

  %w[search random download].each do |command|
    it "reports a read timeout from #{command} as a CLI error" do
      args, path = case command
                   when 'search' then [%w[search cat], '/search?q=cat']
                   when 'random' then [%w[random], '/cat.html']
                   when 'download' then [['download', page_url, '--output', 'unused'], '/cat.html']
                   end
      allow(Irasutoya::Cli::Illustration).to receive(:random_url).and_return(page_url) if command == 'random'
      allow(respond(path)).to receive(:read_body).and_raise(Net::ReadTimeout)

      message = "HTML request timed out for https://#{host}#{path}"
      message = "Could not fetch illustration page #{page_url}: #{message}" if command == 'download'
      expect do
        expect { Irasutoya::Cli::Runner.start(args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("#{message}\n").to_stderr.and output('').to_stdout
    end
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

  it 'stops after the redirect limit' do
    redirect = respond('/cat.html', Net::HTTPFound.new('1.1', '302', 'Found'))
    redirect['location'] = '/cat.html'
    expect(http).to receive(:request_get).with('/cat.html', headers).exactly(6).times.and_yield(redirect)

    expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url) }
      .to raise_error(described_class::Error, 'Too many HTML redirects')
  end

  { missing: nil, empty: '', blank: ' ' }.each do |kind, location|
    it "rejects a #{kind} Location header without making a second request" do
      redirect = Net::HTTPFound.new('1.1', '302', 'Found')
      redirect['location'] = location if location
      expect(http).to receive(:request_get).with('/cat.html', headers).once.and_yield(redirect)

      expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url) }
        .to raise_error(described_class::Error, 'Invalid HTTPS redirect for HTML page')
    end
  end

  it 'rejects malformed redirect destinations' do
    redirect = respond('/cat.html', Net::HTTPFound.new('1.1', '302', 'Found'))
    redirect['location'] = 'http://['

    expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url) }
      .to raise_error(described_class::Error, 'Invalid HTTPS redirect for HTML page')
  end

  def route_search_to(origin)
    allow(Irasutoya::Cli::Illustration).to receive(:fetch_page_and_parse).and_wrap_original do |fetch, url|
      fetch.call(origin + URI.parse(url).request_uri)
    end
  end

  def run_search
    Irasutoya::Cli::Runner.start(%w[search cat --jsonl])
  end

  def result_urls(stdout)
    stdout.lines.map { |line| JSON.parse(line).fetch('page_url') }
  end

  def serve_html(context, connections, other_origin: nil, oversized: nil, stalled: nil, truncated: nil)
    TCPServer.open('127.0.0.1', 0) do |server|
      origin = "https://#{host}:#{server.addr[1]}"
      list = %w[first second third].map do |name|
        detail_origin = name == 'second' && other_origin ? other_origin : origin
        %(<div class="box"><a href="#{detail_origin}/#{name}.html"></a><a>Cat</a></div>)
      end.join
      tls_server = OpenSSL::SSL::SSLServer.new(server, context)
      worker = Thread.new do
        connections.each do |paths|
          socket = tls_server.accept
          paths.each { |path| respond_to_html(socket, path, list, oversized:, stalled:, truncated:) }
          expect(socket.gets).to be_nil unless paths.last == truncated
        ensure
          socket&.close
        end
      end
      yield origin
      expect(worker.join(5)).to eq(worker)
    ensure
      worker&.kill&.join
    end
  end

  def respond_to_html(socket, path, list, oversized:, stalled:, truncated:)
    expect(socket.gets).to eq("GET #{path} HTTP/1.1\r\n")
    socket.to_enum(:each_line).take_while { |line| line != "\r\n" }
    return write_oversized_chunk(socket) if path == oversized
    return socket.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\na") if path == stalled

    body = path == '/search?q=cat' ? list : detail
    length = body.bytesize
    body = body.byteslice(0, 10) if path == truncated
    socket.write("HTTP/1.1 200 OK\r\nContent-Length: #{length}\r\n\r\n#{body}")
  end

  def respond(path, response = Net::HTTPOK.new('1.1', '200', 'OK'))
    allow(http).to receive(:request_get).with(path, headers).and_yield(response)
    response
  end

  def with_tls_server
    context = local_tls_context
    store = OpenSSL::X509::Store.new
    store.add_cert(context.cert)
    allow(Net::HTTP).to receive(:start).and_wrap_original do |start, host, port, **options, &request|
      start.call(host, port, nil, **options, cert_store: store, read_timeout: 1, &request)
    end

    TCPServer.open('127.0.0.1', 0) do |server|
      tls_server = OpenSSL::SSL::SSLServer.new(server, context)
      yield tls_server, "https://127.0.0.1:#{server.addr[1]}/cat.html"
    end
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
    cert.add_extension(OpenSSL::X509::ExtensionFactory.new.create_extension('subjectAltName', 'IP:127.0.0.1,DNS:www.irasutoya.com'))
    cert.sign(key, OpenSSL::Digest.new('SHA256'))

    OpenSSL::SSL::SSLContext.new.tap do |context|
      context.cert = cert
      context.key = key
    end
  end

  def serve_unterminated_chunk(server)
    socket = server.accept
    socket.each_line { |line| break if line == "\r\n" }
    write_oversized_chunk(socket)
    socket.read
  ensure
    socket&.close
  end

  def serve_slow_redirect_and_body(server)
    socket = server.accept
    socket.each_line { |line| break if line == "\r\n" }
    sleep 0.65
    socket.write("HTTP/1.1 302 Found\r\nLocation: /next.html\r\nContent-Length: 0\r\n\r\n")
    socket.close

    socket = server.accept
    socket.each_line { |line| break if line == "\r\n" }
    socket.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n8\r\n")
    8.times do
      socket.write('a')
      sleep 0.08
    end
    socket.write("\r\n0\r\n\r\n")
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    # The client can close the connection while the response is still being written.
  ensure
    socket&.close
  end

  def write_oversized_chunk(socket)
    bytes = described_class::MAX_BYTES + 1
    socket.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n#{bytes.to_s(16)}\r\n" + ('a' * bytes))
  end

  def stream_oversized_detail
    response = respond('/cat.html')
    response['transfer-encoding'] = 'chunked'
    expect(http).to receive(:finish).at_least(:once) { allow(http).to receive(:started?).and_return(false) }
    expect(response).to receive(:read_body) do |&receive_chunk|
      receive_chunk.call(detail.ljust(256))
      receive_chunk.call('猫')
      raise 'Read continued after the HTML limit was exceeded'
    end
  end
end
