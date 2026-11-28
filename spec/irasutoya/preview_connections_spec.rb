# frozen_string_literal: true

require 'irasutoya'
require 'irasutoya/cli/illustration'
require 'net/http'
require 'openssl'
require 'socket'
require 'irasutoya/cli/preview'

RSpec.describe Irasutoya::Cli::Runner do
  let(:runner) { described_class.new([], {}, shell: Thor::Shell::Basic.new) }
  let(:rendered) { [] }
  let(:page_url) { 'https://www.irasutoya.com/first.html' }
  let(:later_page_url) { 'https://www.irasutoya.com/second.html' }
  let(:key) { OpenSSL::PKey::RSA.new(2048) }
  let(:certificate) do
    OpenSSL::X509::Certificate.new.tap do |cert|
      cert.version = 2
      cert.serial = 1
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=127.0.0.1')
      cert.public_key = key.public_key
      cert.not_before = Time.now - 60
      cert.not_after = Time.now + 60
      cert.add_extension(OpenSSL::X509::ExtensionFactory.new.create_extension('subjectAltName', 'IP:127.0.0.1'))
      cert.sign(key, OpenSSL::Digest.new('SHA256'))
    end
  end
  let(:tls_context) do
    OpenSSL::SSL::SSLContext.new.tap do |context|
      context.cert = certificate
      context.key = key
    end
  end

  before do
    allow($stdout).to receive(:tty?).and_return(true)
    allow(runner).to receive(:say)
    allow(Irasutoya::Cli::Preview).to receive(:show) { |file| rendered << file.read }
    store = OpenSSL::X509::Store.new
    store.add_cert(certificate)
    allow(Net::HTTP).to receive(:start).and_wrap_original do |start, host, port, **options|
      start.call(host, port, **options, cert_store: store)
    end
  end

  context 'when fetching the random selection and detail page' do
    let(:feed_host) { 'www.irasutoya.com' }
    let(:feed_path) { '/feeds/posts/summary?start-index=1&max-results=1&alt=json-in-script' }
    let(:detail_response) { ['/cat.html', '200 OK', {}, '<div class="entry">Cat</div>'] }

    before do
      allow(Irasutoya::Cli::Illustration).to receive(:random_api_path).and_return(feed_path)
    end

    it 'sends both GETs on one HTTPS connection for the same origin' do
      url = "https://#{feed_host}/cat.html"
      serve_https([feed_response(url), detail_response]) do |origin|
        route_random_requests(feed_host => origin)

        runner.random

        expect(runner).to have_received(:say).with("Page URL:    #{url}")
      end
    end

    it 'opens a separate HTTPS connection for a different origin' do
      detail_host = 'irasutoya.com'
      url = "https://#{detail_host}/cat.html"
      serve_https([detail_response]) do |detail_origin|
        serve_https([feed_response(url)]) do |feed_origin|
          route_random_requests(feed_host => feed_origin, detail_host => detail_origin)

          runner.random

          expect(runner).to have_received(:say).with("Page URL:    #{url}")
        end
      end
    end

    it 'discards the feed connection after an unsuccessful status' do
      response = [feed_path, '503 Service Unavailable', { 'Content-Length' => '1' }]
      expect_feed_retry(response, /HTTP 503/)
    end

    it 'discards the feed connection when a chunked response exceeds the byte limit midstream' do
      limit = Irasutoya::Cli::Illustration::MAX_FEED_BYTES
      body = "1\r\na\r\n#{limit.to_s(16)}\r\n#{'b' * limit}"
      response = [feed_path, '200 OK', { 'Transfer-Encoding' => 'chunked' }, body]
      expect_feed_retry(response, /byte limit/)
    end

    def expect_feed_retry(response, error)
      url = "https://#{feed_host}/cat.html"
      serve_https([response], [feed_response(url), detail_response]) do |origin|
        route_random_requests(feed_host => origin)

        Irasutoya::Cli::HtmlPage.with_sessions do
          expect { Irasutoya::Cli::Illustration.random }.to raise_error(Irasutoya::Cli::Illustration::FeedError, error)
          expect(Irasutoya::Cli::Illustration.random.url).to eq(url)
        end
      end
    end

    def feed_response(url)
      entry = { link: [{ rel: 'alternate', href: url }] }
      [feed_path, '200 OK', {}, "callback(#{JSON.generate(feed: { entry: [entry] })});"]
    end

    def route_random_requests(origins)
      store = OpenSSL::X509::Store.new
      store.add_cert(certificate)
      allow(Net::HTTP).to receive(:start).and_wrap_original do |start, host, _port, **options, &block|
        target = URI(origins.fetch(host))
        start.call(target.host, target.port, nil, **options, cert_store: store, open_timeout: 2, read_timeout: 2, &block)
      end
    end
  end

  it 'reuses one connection across search results and follows a bodyless same-origin redirect' do
    serve_https([
      ['/first.png', '302 Found', { 'Location' => '/redirected.png' }, ''],
      ['/redirected.png', '200 OK', {}, 'first'],
      ['/second.png', '200 OK', {}, 'second']
    ]) do |origin|
      links = %w[first second].map do |name|
        result = illustration("#{origin}/#{name}.png", url: "https://www.irasutoya.com/#{name}.html")
        instance_double(Irasutoya::IrasutoLink, show_url: result.url, fetch_irasuto: result)
      end
      allow(Irasutoya::Cli::Illustration).to receive(:search).with(query: 'query').and_return(links)

      runner.search('query')

      expect(rendered).to eq(%w[first second])
    end
  end

  {
    'empty' => ['', ''],
    'unsupported' => ['ftp://example.com/image.png', 'ftp://example.com/image.png'],
    'malformed with control characters' => ["https://example.com/\e", 'https://example.com/\x1B']
  }.each do |kind, (invalid_url, escaped_url)|
    it "warns once and continues the search when an image URL is #{kind}" do
      serve_https([['/first.png', '200 OK', {}, 'first'], ['/second.png', '200 OK', {}, 'second']]) do |origin|
        first = Irasutoya::Irasuto.new(url: page_url, title: 'First', description: '',
                                      image_urls: [invalid_url, "#{origin}/first.png"])
        second = illustration("#{origin}/second.png", url: later_page_url)
        links = [first, second].map do |result|
          instance_double(Irasutoya::IrasutoLink, show_url: result.url, fetch_irasuto: result)
        end
        allow(Irasutoya::Irasuto).to receive(:search).with(query: 'query').and_return(links)

        runner.search('query')

        expect(runner).to have_received(:say).with(start_with("warn: Could not preview #{escaped_url}:"), :yellow).once
        expect(runner).to have_received(:say).with(start_with('warn:'), :yellow).once
        expect(runner).to have_received(:say).with("Page URL:    #{second.url}")
        expect(Net::HTTP).to have_received(:start).once
        expect(rendered).to eq(%w[first second])
      end
    end
  end

  it 'warns once on the sixth redirect and previews the next image and search result' do
    redirects = (0...6).map do |index|
      ["/redirect-#{index}.png", '302 Found', { 'Location' => "/redirect-#{index + 1}.png" }, '']
    end
    serve_https([*redirects, ['/next.png', '200 OK', {}, 'next'], ['/later.png', '200 OK', {}, 'later']]) do |origin|
      failed_url = "#{origin}/redirect-0.png"
      later_url = "#{origin}/later.png"
      results = [illustration(failed_url, "#{origin}/next.png"), illustration(later_url, url: later_page_url)]
      links = results.map { |result| instance_double(Irasutoya::IrasutoLink, show_url: result.url, fetch_irasuto: result) }
      allow(Irasutoya::Cli::Illustration).to receive(:search).with(query: 'query').and_return(links)

      runner.search('query')

      expect(runner).to have_received(:say).with("warn: Could not preview #{failed_url}: Too many image redirects", :yellow)
      expect(runner).to have_received(:say).with(start_with('warn:'), :yellow).once
      expect(runner).to have_received(:say).with("Page URL:    #{later_page_url}")
      expect(rendered).to eq(%w[next later])
    end
  end

  it 'warns once when the first preview connection is refused and continues previewing search results' do
    refused_url = 'https://refused.example/first.png'
    allow(Net::HTTP).to receive(:start).with('refused.example', 443, any_args).and_raise(Errno::ECONNREFUSED)

    serve_https([['/next.png', '200 OK', {}, 'next']]) do |origin|
      results = [illustration(refused_url), illustration("#{origin}/next.png", url: later_page_url)]
      links = results.map { |result| instance_double(Irasutoya::IrasutoLink, show_url: result.url, fetch_irasuto: result) }
      allow(Irasutoya::Cli::Illustration).to receive(:search).with(query: 'query').and_return(links)

      runner.search('query')

      expect(runner).to have_received(:say).with(start_with("warn: Could not preview #{refused_url}:"), :yellow).once
      expect(runner).to have_received(:say).with(start_with('warn:'), :yellow).once
      expect(runner).to have_received(:say).with("Page URL:    #{results.last.url}")
      expect(rendered).to eq(['next'])
    end
  end

  it 'warns once when a connection closes before headers and continues previewing search results' do
    serve_https(
      [['/closed.png']],
      [['/first.png', '200 OK', {}, 'first'], ['/second.png', '200 OK', {}, 'second']]
    ) do |origin|
      closed_url = "#{origin}/closed.png"
      later_url = "#{origin}/second.png"
      results = [illustration(closed_url, "#{origin}/first.png"), illustration(later_url, url: later_page_url)]
      links = results.map { |result| instance_double(Irasutoya::IrasutoLink, show_url: result.url, fetch_irasuto: result) }
      allow(Irasutoya::Cli::Illustration).to receive(:search).with(query: 'query').and_return(links)

      runner.search('query')

      expect(runner).to have_received(:say).with(start_with("warn: Could not preview #{closed_url}:"), :yellow).once
      expect(runner).to have_received(:say).with("Page URL:    #{later_page_url}")
      expect(rendered).to eq(%w[first second])
    end
  end

  it 'warns once when a trickling body exceeds the deadline and previews the next image' do
    stub_const('Irasutoya::Cli::ImageTransfer::TRANSFER_TIMEOUT', 0.25)
    serve_https(
      [['/slow.png', '200 OK', {}, 'x' * 20, 0.05]],
      [['/next.png', '200 OK', {}, 'next']]
    ) do |origin|
      slow_url = "#{origin}/slow.png"
      allow(Irasutoya::Cli::Illustration).to receive(:random).and_return(illustration(slow_url, "#{origin}/next.png"))

      runner.random

      expect(runner).to have_received(:say).with(start_with('warn:'), :yellow).once
      expect(runner).to have_received(:say)
        .with("warn: Could not preview #{slow_url}: Image transfer deadline exceeded", :yellow)
      expect(rendered).to eq(['next'])
    end
  end

  it 'reports the deadline while a chunk is stalled and previews the next image on a fresh connection' do
    stub_const('Irasutoya::Cli::ImageTransfer::TRANSFER_TIMEOUT', 0.25)
    serve_https(
      [['/stalled.png', '200 OK', { 'Transfer-Encoding' => 'chunked' }, "2\r\nx"]],
      [['/next.png', '200 OK', {}, 'next']]
    ) do |origin|
      stalled_url = "#{origin}/stalled.png"
      allow(Irasutoya::Cli::Illustration).to receive(:random)
        .and_return(illustration(stalled_url, "#{origin}/next.png"))

      Timeout.timeout(3) { runner.random }

      expect(runner).to have_received(:say)
        .with("warn: Could not preview #{stalled_url}: Image transfer deadline exceeded", :yellow).once
      expect(rendered).to eq(['next'])
    end
  end

  it 'rejects oversized headers while the server withholds the body and previews the next image' do
    stub_const('Irasutoya::Cli::ImageTransfer::MAX_IMAGE_BYTES', 4)
    serve_https(
      [['/oversized.png', '200 OK', { 'Content-Length' => '5' }]],
      [['/next.png', '200 OK', {}, 'next']]
    ) do |origin|
      allow(Irasutoya::Cli::Illustration).to receive(:random)
        .and_return(illustration("#{origin}/oversized.png", "#{origin}/next.png"))

      Timeout.timeout(5) { runner.random }

      expect(runner).to have_received(:say).with("warn: Image preview exceeds the 4-byte limit", :yellow).once
      expect(rendered).to eq(['next'])
    end
  end

  it 'warns once for a malformed Content-Length and previews the next image on a fresh connection' do
    serve_https(
      [['/malformed.png', '200 OK', { 'Content-Length' => 'oops' }]],
      [['/next.png', '200 OK', {}, 'next']]
    ) do |origin|
      malformed_url = "#{origin}/malformed.png"
      allow(Irasutoya::Cli::Illustration).to receive(:random)
        .and_return(illustration(malformed_url, "#{origin}/next.png"))

      Timeout.timeout(5) { runner.random }

      expect(runner).to have_received(:say)
        .with("warn: Could not preview #{malformed_url}: wrong Content-Length format", :yellow).once
      expect(runner).to have_received(:say).with(start_with('warn:'), :yellow).once
      expect(rendered).to eq(['next'])
    end
  end

  it 'warns once for an empty response and renders the next image' do
    serve_https(
      [['/empty.png', '200 OK']],
      [['/next.png', '200 OK', {}, 'image']]
    ) do |origin|
      empty_url = "#{origin}/empty.png"
      allow(Irasutoya::Cli::Illustration).to receive(:random).and_return(illustration(empty_url, "#{origin}/next.png"))

      runner.random

      expect(runner).to have_received(:say).with("warn: Could not preview #{empty_url}: Empty image response", :yellow).once
      expect(runner).to have_received(:say).with(start_with('warn:'), :yellow).once
      expect(rendered).to eq(['image'])
    end
  end

  it 'uses a separate connection across origins and closes both sessions when rendering fails' do
    serve_https([['/image.png', '200 OK', {}, 'image']]) do |target|
      serve_https([['/redirect.png', '302 Found', { 'Location' => "#{target}/image.png" }, '']]) do |origin|
        allow(Irasutoya::Cli::Illustration).to receive(:random).and_return(illustration("#{origin}/redirect.png"))
        allow(Irasutoya::Cli::Preview).to receive(:show).and_raise(IOError, 'render failed')

        expect { runner.random }.to raise_error(IOError, 'render failed')
      end
    end
  end

  it 'closes the least recently used session before opening another origin' do
    stub_const('Irasutoya::Cli::SessionCache::MAX_SESSIONS', 2)
    sessions = []
    store = OpenSSL::X509::Store.new
    store.add_cert(certificate)
    allow(Net::HTTP).to receive(:start).and_wrap_original do |start, host, port, **options|
      expect(sessions.count(&:started?)).to be < 2
      start.call(host, port, **options, cert_store: store).tap { |http| sessions << http }
    end

    serve_https(%w[a1 a2 a3 a4].map { |name| ["/#{name}.png", '200 OK', {}, name] }) do |first|
      serve_https([['/b1.png', '200 OK', {}, 'b1']], [['/b2.png', '200 OK', {}, 'b2']]) do |second|
        serve_https([['/c1.png', '200 OK', {}, 'c1']]) do |third|
          urls = ["#{first}/a1.png", "#{first}/a2.png", "#{second}/b1.png", "#{first}/a3.png",
                  "#{third}/c1.png", "#{first}/a4.png", "#{second}/b2.png"]
          allow(Irasutoya::Cli::Illustration).to receive(:random).and_return(illustration(*urls))

          runner.random

          expect(rendered).to eq(%w[a1 a2 b1 a3 c1 a4 b2])
          expect(sessions.size).to eq(4)
          expect(sessions).to all(have_attributes(started?: false))
        end
      end
    end
  end

  [
    ['missing', nil, 'is missing a Location header value'],
    ['blank', '', 'is missing a Location header value'],
    ['invalid', 'https://[', 'has an invalid Location header'],
    ['hostless', 'https:///image.png', 'has an invalid Location header'],
    ['missing its authority', '///image.png', 'has an invalid Location header'],
    ['using an out-of-range port', 'https://127.0.0.1:65536/image.png', 'has an invalid Location header'],
    ['non-HTTPS', 'http://127.0.0.1/image.png', 'must use HTTPS'],
    ['non-HTTP', 'file:///image.png', 'must use HTTPS']
  ].each do |kind, location, error|
    it "warns once and renders the next image when the redirect location is #{kind}" do
      headers = location.nil? ? {} : { 'Location' => location }
      serve_https([
        ['/first.png', '302 Found', headers, ''],
        ['/second.png', '200 OK', {}, 'second']
      ]) do |origin|
        first = "#{origin}/first.png"
        allow(Irasutoya::Cli::Illustration).to receive(:random).and_return(illustration(first, "#{origin}/second.png"))

        runner.random

        expect(runner).to have_received(:say).with("warn: Could not preview #{first}: Image redirect #{error}", :yellow).once
        expect(runner).to have_received(:say).with(start_with('warn:'), :yellow).once
        expect(rendered).to eq(['second'])
      end
    end
  end

  def illustration(*image_urls, url: page_url)
    Irasutoya::Irasuto.new(url:, title: 'Title', description: 'Description', image_urls:)
  end

  def serve_https(*connections)
    TCPServer.open('127.0.0.1', 0) do |server|
      worker = Thread.new do
        tls_server = OpenSSL::SSL::SSLServer.new(server, tls_context)
        connections.each do |responses|
          tls_server.accept.tap do |socket|
            responses.each { |response| respond_to_request(socket, *response) }
            expect(socket.gets).to be_nil if responses.last.length > 1
          ensure
            socket.close
          end
        end
      end
      begin
        yield "https://127.0.0.1:#{server.addr[1]}"
        expect(worker.join(5)).to eq(worker)
      ensure
        worker.kill.join if worker.alive?
      end
    end
  end

  def respond_to_request(socket, path, status = nil, headers = {}, body = '', delay = nil)
    expect(socket.gets).to eq("GET #{path} HTTP/1.1\r\n")
    socket.to_enum(:each_line).take_while { |line| line != "\r\n" }
    return unless status

    socket.write("HTTP/1.1 #{status}\r\n")
    { 'Content-Length' => body.bytesize }.merge(headers).each { |name, value| socket.write("#{name}: #{value}\r\n") }
    socket.write("\r\n")
    return socket.write(body) unless delay

    body.each_char do |byte|
      socket.write(byte)
      break if IO.select([socket], nil, nil, delay)
    end
  end
end
