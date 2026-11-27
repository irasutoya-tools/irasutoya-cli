# frozen_string_literal: true

require 'socket'

RSpec.describe 'Random selection feed deadline' do
  let(:error_message) { "Random selection feed deadline exceeded\n" }

  before do
    stub_const('Irasutoya::Cli::Illustration::FEED_TIMEOUT', 0.5)
  end

  it 'closes a feed that keeps making read progress and exits before fetching a detail' do
    with_feed_server(use_ssl: false) do |socket|
      request = socket.gets
      expect(request).to start_with('GET /feeds/posts/summary?')
      socket.each_line.take_while { |line| line != "\r\n" }
      socket.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\na")
      # The first chunk stays complete while its terminator arrives one byte at a time.
      slices = ["\r", "\n", "1\r\na", "\r", "\n", "0\r\n\r\n"]
      written = slices.take_while do |bytes|
        next false if IO.select([socket], nil, nil, 0.12)

        socket.write(bytes)
        true
      end
      expect(written.length).to be_between(2, slices.length - 1)
      expect(socket.read).to eq('')
    end
  end

  it 'closes the socket when the TLS handshake stalls' do
    with_feed_server(use_ssl: true) do |socket|
      expect(socket.read).not_to be_empty
    end
  end

  it 'surfaces a socket timeout as a feed error' do
    allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)

    expect { Irasutoya::Cli::Illustration.random }
      .to raise_error(Irasutoya::Cli::Illustration::FeedError, 'Random selection feed request timed out')
  end

  it 'surfaces a DNS failure as a feed error instead of crashing' do
    allow(Net::HTTP).to receive(:start).and_raise(SocketError)

    expect { Irasutoya::Cli::Illustration.random }
      .to raise_error(Irasutoya::Cli::Illustration::FeedError, 'Random selection feed could not resolve host')
  end

  it 'surfaces a refused connection as a feed error instead of crashing' do
    allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

    expect { Irasutoya::Cli::Illustration.random }
      .to raise_error(Irasutoya::Cli::Illustration::FeedError, /\ARandom selection feed connection failed: /)
  end

  it 'surfaces a TLS handshake failure as a feed error instead of crashing' do
    allow(Net::HTTP).to receive(:start).and_raise(OpenSSL::SSL::SSLError)

    expect { Irasutoya::Cli::Illustration.random }
      .to raise_error(Irasutoya::Cli::Illustration::FeedError, 'Random selection feed TLS handshake failed')
  end

  it 'exits cleanly with a Thor error when the random command cannot resolve the feed host' do
    allow(Net::HTTP).to receive(:start).and_raise(SocketError)

    expect do
      expect { Irasutoya::Cli::Runner.start(['random']) }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Random selection feed could not resolve host\n").to_stderr.and output('').to_stdout
  end

  def with_feed_server(use_ssl:)
    TCPServer.open('127.0.0.1', 0) do |server|
      expect(Net::HTTP).to receive(:start).once.and_wrap_original do |start, host, _port, **options, &request|
        expect(host).to eq('www.irasutoya.com')
        start.call('127.0.0.1', server.addr[1], nil, **options.merge(use_ssl:, read_timeout: 0.4), &request)
      end

      worker = Thread.new do
        socket = server.accept
        yield socket
      ensure
        socket&.close
      end

      expect_command_failure
      expect(worker.join(2)).to eq(worker)
    ensure
      worker&.kill&.join
    end
  end

  def expect_command_failure
    expect(Irasutoya::IrasutoLink).not_to receive(:new)
    expect do
      expect { Irasutoya::Cli::Runner.start(['random']) }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(error_message).to_stderr.and output('').to_stdout
  end
end
