# frozen_string_literal: true

require 'irasutoya'
require 'socket'
require 'terminal_image'

RSpec.describe Irasutoya::Cli::Runner do
  let(:runner) { described_class.new([], {}, shell: Thor::Shell::Basic.new) }
  let(:rendered) { [] }

  before do
    allow($stdout).to receive(:tty?).and_return(true)
    allow(runner).to receive(:say)
    allow(TerminalImage).to receive(:show) { |file| rendered << file.read }
  end

  it 'reuses one connection across search results and follows a bodyless same-origin redirect' do
    serve_previews([
      ['/first.png', '302 Found', { 'Location' => '/redirected.png' }, ''],
      ['/redirected.png', '200 OK', {}, 'first'],
      ['/second.png', '200 OK', {}, 'second']
    ]) do |origin|
      links = %w[first second].map do |name|
        result = illustration("#{origin}/#{name}.png")
        instance_double(Irasutoya::IrasutoLink, fetch_irasuto: result)
      end
      allow(Irasutoya::Irasuto).to receive(:search).with(query: 'query').and_return(links)

      runner.search('query')

      expect(rendered).to eq(%w[first second])
    end
  end

  it 'uses a separate connection across origins and closes both sessions when rendering fails' do
    serve_previews([['/image.png', '200 OK', {}, 'image']]) do |target|
      serve_previews([['/redirect.png', '302 Found', { 'Location' => "#{target}/image.png" }, '']]) do |origin|
        allow(Irasutoya::Irasuto).to receive(:random).and_return(illustration("#{origin}/redirect.png"))
        allow(TerminalImage).to receive(:show).and_raise(IOError, 'render failed')

        expect { runner.random }.to raise_error(IOError, 'render failed')
      end
    end
  end

  def illustration(image_url)
    Irasutoya::Irasuto.new(url: image_url, title: 'Title', description: 'Description', image_urls: [image_url])
  end

  def serve_previews(responses)
    TCPServer.open('127.0.0.1', 0) do |server|
      worker = Thread.new do
        socket = server.accept
        responses.each { |response| respond_to_preview(socket, *response) }
        expect(socket.gets).to be_nil
      ensure
        socket&.close
      end
      begin
        yield "http://127.0.0.1:#{server.addr[1]}"
        expect(worker.join(5)).to eq(worker)
      ensure
        worker.kill.join if worker.alive?
      end
    end
  end

  def respond_to_preview(socket, path, status, headers, body)
    expect(socket.gets).to eq("GET #{path} HTTP/1.1\r\n")
    socket.each_line.take_while { |line| line != "\r\n" }
    socket.write("HTTP/1.1 #{status}\r\nContent-Length: #{body.bytesize}\r\n")
    headers.each { |name, value| socket.write("#{name}: #{value}\r\n") }
    socket.write("\r\n#{body}")
  end
end
