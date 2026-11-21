# frozen_string_literal: true

require 'irasutoya'
require 'socket'
require 'irasutoya/cli/preview'

RSpec.describe Irasutoya::Cli::Runner do
  let(:runner) { described_class.new([], {}, shell: Thor::Shell::Basic.new) }
  let(:rendered) { [] }

  before do
    allow($stdout).to receive(:tty?).and_return(true)
    allow(runner).to receive(:say)
    allow(Irasutoya::Cli::Preview).to receive(:show) { |file| rendered << file.read }
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

  it 'warns once when a connection closes before headers and continues previewing search results' do
    serve_previews(
      [['/closed.png']],
      [['/first.png', '200 OK', {}, 'first'], ['/second.png', '200 OK', {}, 'second']]
    ) do |origin|
      closed_url = "#{origin}/closed.png"
      later_url = "#{origin}/second.png"
      results = [illustration(closed_url, "#{origin}/first.png"), illustration(later_url)]
      links = results.map { |result| instance_double(Irasutoya::IrasutoLink, fetch_irasuto: result) }
      allow(Irasutoya::Irasuto).to receive(:search).with(query: 'query').and_return(links)

      runner.search('query')

      expect(runner).to have_received(:say).with(start_with("warn: Could not preview #{closed_url}:"), :yellow).once
      expect(runner).to have_received(:say).with("Page URL:    #{later_url}")
      expect(rendered).to eq(%w[first second])
    end
  end

  it 'uses a separate connection across origins and closes both sessions when rendering fails' do
    serve_previews([['/image.png', '200 OK', {}, 'image']]) do |target|
      serve_previews([['/redirect.png', '302 Found', { 'Location' => "#{target}/image.png" }, '']]) do |origin|
        allow(Irasutoya::Irasuto).to receive(:random).and_return(illustration("#{origin}/redirect.png"))
        allow(Irasutoya::Cli::Preview).to receive(:show).and_raise(IOError, 'render failed')

        expect { runner.random }.to raise_error(IOError, 'render failed')
      end
    end
  end

  def illustration(*image_urls)
    Irasutoya::Irasuto.new(url: image_urls.first, title: 'Title', description: 'Description', image_urls:)
  end

  def serve_previews(*connections)
    TCPServer.open('127.0.0.1', 0) do |server|
      worker = Thread.new do
        connections.each do |responses|
          server.accept.tap do |socket|
            responses.each { |response| respond_to_preview(socket, *response) }
            expect(socket.gets).to be_nil if responses.last.length > 1
          ensure
            socket.close
          end
        end
      end
      begin
        yield "http://127.0.0.1:#{server.addr[1]}"
        expect(worker.join(5)).to eq(worker)
      ensure
        worker.kill.join if worker.alive?
      end
    end
  end

  def respond_to_preview(socket, path, status = nil, headers = {}, body = '')
    expect(socket.gets).to eq("GET #{path} HTTP/1.1\r\n")
    socket.each_line.take_while { |line| line != "\r\n" }
    return unless status

    socket.write("HTTP/1.1 #{status}\r\nContent-Length: #{body.bytesize}\r\n")
    headers.each { |name, value| socket.write("#{name}: #{value}\r\n") }
    socket.write("\r\n#{body}")
  end
end
