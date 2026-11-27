# frozen_string_literal: true

require 'stringio'
require 'openssl'
require 'socket'

RSpec.describe Irasutoya::Cli::ImageTransfer do
  let(:headers) { { 'Accept-Encoding' => 'identity' } }
  let(:http) { instance_double(Net::HTTP, started?: true, finish: nil) }
  let(:url) { URI('https://example.com/images/start.png') }

  before do
    allow(Net::HTTP).to receive(:start).with('example.com', 443, use_ssl: true, max_retries: 0, ignore_eof: false).and_return(http)
  end

  describe '.copy' do
    let(:image) { Net::HTTPOK.new('1.1', '200', 'OK') }
    let(:destination) { StringIO.new('prefix'.dup, 'ab') }

    before do
      allow(http).to receive(:request_get).with('/images/start.png', headers).and_yield(image)
    end

    it 'copies exactly the supplied number of bytes regardless of destination position' do
      image['Content-Length'] = '4'
      allow(image).to receive(:read_body).and_yield('é').and_yield('ab')

      described_class.copy(url, destination, max_bytes: 4)

      expect(destination.string).to eq('prefixéab'.b)
    end

    it 'stops before writing an overflowing chunk without Content-Length' do
      allow(image).to receive(:read_body) do |&receive_chunk|
        receive_chunk.call('é')
        receive_chunk.call('abc')
        raise 'Read past the byte limit'
      end

      expect do
        described_class.copy(url, destination, max_bytes: 4)
      end.to raise_error(described_class::SizeLimitExceededError)
      expect(destination.string).to eq('prefixé'.b)
    end
  end

  it 'resolves a relative redirect and yields only the successful response body' do
    redirect = redirect_to('next.png?size=large')
    image = Net::HTTPOK.new('1.1', '200', 'OK')
    expect(http).to receive(:request_get).with('/images/start.png', headers).ordered.and_yield(redirect)
    expect(redirect).not_to receive(:read_body)
    expect(http).to receive(:request_get).with('/images/next.png?size=large', headers).ordered.and_yield(image)
    allow(image).to receive(:read_body).and_yield('first').and_yield('second')

    expect { |chunks| described_class.fetch(url, &chunks) }.to yield_successive_args('first', 'second')
  end

  it 'yields the image after exactly five redirects' do
    paths = ['/images/start.png', *1.upto(5).map { |index| "/images/#{index}.png" }]
    paths.each_cons(2) do |source, target|
      expect(http).to receive(:request_get).with(source, headers).ordered.and_yield(redirect_to(target))
    end
    image = Net::HTTPOK.new('1.1', '200', 'OK')
    expect(http).to receive(:request_get).with(paths.last, headers).ordered.and_yield(image)
    allow(image).to receive(:read_body).and_yield('image')

    expect { |chunks| described_class.fetch(url, &chunks) }.to yield_with_args('image')
  end

  it 'shares the deadline between a redirect and the final response' do
    stub_const('Irasutoya::Cli::ImageTransfer::TRANSFER_TIMEOUT', 0.25)
    redirect = redirect_to('next.png')
    image = Net::HTTPOK.new('1.1', '200', 'OK')
    expect(http).to receive(:request_get).with('/images/start.png', headers).ordered do |&receive_response|
      sleep 0.15
      receive_response.call(redirect)
    end
    expect(http).to receive(:request_get).with('/images/next.png', headers).ordered.and_yield(image)
    allow(image).to receive(:read_body) do |&receive_chunk|
      sleep 0.15
      receive_chunk.call('image')
    end

    expect do
      described_class.fetch(url) { raise 'Unexpected image bytes' }
    end.to raise_error(described_class::ResponseError, 'Image transfer deadline exceeded')
  end

  it 'rejects a sixth redirect before requesting its destination' do
    paths = ['/images/start.png', *1.upto(6).map { |index| "/images/#{index}.png" }]
    paths.each_cons(2) do |source, target|
      expect(http).to receive(:request_get).with(source, headers).ordered.and_yield(redirect_to(target))
    end

    expect do
      described_class.fetch(url) { raise 'Unexpected image bytes' }
    end.to raise_error(Irasutoya::Cli::Error, 'Too many image redirects')
  end

  it 'reports an unsuccessful status without yielding its body' do
    missing = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
    allow(http).to receive(:request_get).with('/images/start.png', headers).and_yield(missing)

    expect do
      described_class.fetch(url) { raise 'Unexpected image bytes' }
    end.to raise_error(described_class::ResponseError, '404 "Not Found"')
  end

  it 'reports an unexpected EOF while reading a chunked body' do
    image = Net::HTTPOK.new('1.1', '200', 'OK')
    image['Transfer-Encoding'] = 'chunked'
    image['Content-Length'] = '12'
    expect(image).not_to receive(:content_length)
    allow(http).to receive(:request_get).with('/images/start.png', headers).and_yield(image)
    allow(image).to receive(:read_body).and_raise(EOFError, 'end of file reached')

    expect do
      described_class.fetch(url) { raise 'Unexpected image bytes' }
    end.to raise_error(described_class::IncompleteBodyError, 'end of file reached')
  end

  it 'rejects plaintext, non-HTTP, and hostless image URLs before making a request' do
    expect(Net::HTTP).not_to receive(:start)
    %w[http://example.com/image.png file:///image.png https:///image.png].each do |url|
      expect do
        described_class.fetch(URI(url)) { raise 'Unexpected image bytes' }
      end.to raise_error(described_class::InvalidSchemeError, 'Image URL must use HTTPS')
    end
  end

  it 'rejects redirects from HTTPS to HTTP before requesting the destination' do
    expect(http).to receive(:request_get).with('/images/start.png', headers)
      .and_yield(redirect_to('http://example.com/images/next.png'))
    expect do
      described_class.fetch(url) { raise 'Unexpected image bytes' }
    end.to raise_error(Irasutoya::Cli::Error, 'Image redirect must use HTTPS')
  end

  it 'closes an oversized chunked image stream even when the chunk terminator never arrives' do
    with_tls_server do |server, image_url|
      worker = Thread.new { serve_unterminated_chunk(server) }

      expect do
        described_class.fetch(URI(image_url), max_bytes: 256) { raise 'Unexpected image bytes' }
      end.to raise_error(described_class::SizeLimitExceededError, 'Image exceeds the 256-byte limit')
      expect(worker.join(5)).to eq(worker)
    ensure
      worker&.kill&.join
    end
  end

  def redirect_to(location)
    Net::HTTPFound.new('1.1', '302', 'Found').tap { |response| response['location'] = location }
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
      yield tls_server, "https://127.0.0.1:#{server.addr[1]}/image.png"
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
    write_oversized_chunk(socket)
    socket.read
  ensure
    socket&.close
  end

  def write_oversized_chunk(socket)
    bytes = 257
    socket.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n#{bytes.to_s(16)}\r\n#{'a' * bytes}")
  end
end
