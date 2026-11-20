# frozen_string_literal: true

require 'irasutoya'
require 'net/http'
require 'open-uri'
require 'terminal_image'
require 'tmpdir'

RSpec.describe Irasutoya::Cli do # rubocop:disable Metrics/BlockLength
  it 'has a version number' do
    expect(Irasutoya::Cli::VERSION).not_to be nil
  end

  describe '.start' do
    it 'exits with a failure status when search has no query' do
      expect do
        expect { Irasutoya::Cli::Runner.start(['search']) }
          .to raise_error(SystemExit) { |error| expect(error.success?).to be false }
      end.to output(/search/).to_stderr
    end
  end

  it 'describes the search page limit and multiple images in help and the README' do
    description = 'Shows images from up to three result pages. Each page can contain multiple images.'
    readme = File.read(File.expand_path('../../README.md', __dir__))

    expect { Irasutoya::Cli::Runner.start(%w[help search]) }.to output(/#{Regexp.escape(description)}/).to_stdout
    expect(readme).to include("irasutoya search {query}  # #{description}")
  end

  describe 'commands' do # rubocop:disable Metrics/BlockLength
    let(:irasuto) do
      Irasutoya::Irasuto.new(
        url: 'http://example.com',
        title: 'title',
        description: 'description',
        image_urls: %w[http://example.com/test.png http://example.com/test2.png]
      )
    end

    let(:expected) do
      <<~EXPECTED
        Page URL:    #{irasuto.url}
        Title:       #{irasuto.title}
        Description: #{irasuto.description}
        Image URL:   #{irasuto.image_urls.first}
        Image URL:   #{irasuto.image_urls.last}
      EXPECTED
    end

    let(:runner) { Irasutoya::Cli::Runner.new([], {}, shell: Thor::Shell::Basic.new) }
    let(:image_data) { %w[first other] }
    let(:http) { instance_double(Net::HTTP) }
    let(:responses) do
      irasuto.image_urls.zip(image_data).to_h do |url, data|
        response = Net::HTTPOK.new('1.1', '200', 'OK')
        allow(response).to receive(:read_body).and_yield(data.byteslice(0, 2)).and_yield(data.byteslice(2..))
        [URI.parse(url).request_uri, response]
      end
    end

    around do |example|
      original_tmpdir = ENV['TMPDIR']
      Dir.mktmpdir do |tmpdir|
        ENV['TMPDIR'] = tmpdir
        example.run
      end
    ensure
      ENV['TMPDIR'] = original_tmpdir
    end

    before do
      stub_const('Irasutoya::Cli::Runner::MAX_PREVIEW_BYTES', image_data.first.bytesize)
      allow(Net::HTTP).to receive(:start).with('example.com', 80, use_ssl: false, max_retries: 0).and_yield(http)
      responses.each { |path, response| allow(http).to receive(:request_get).with(path).and_yield(response) }
      allow(TerminalImage).to receive(:show)
    end

    shared_examples_for 'a command displays irasuto' do
      it 'prints metadata without downloading or rendering when stdout is redirected' do
        expect(Net::HTTP).not_to receive(:start)
        expect(TerminalImage).not_to receive(:show)

        expect do
          allow($stdout).to receive(:tty?).and_return(false)
          subject
        end.to output(expected).to_stdout
      end

      context 'with terminal control characters in metadata' do
        let(:irasuto) do
          Irasutoya::Irasuto.new(
            url: "http://example.com/\a",
            title: "猫のイラスト\e[2J",
            description: "かわいい猫\r\n説明\t\u009B31m\x7f",
            image_urls: ['http://example.com/test.png']
          )
        end

        let(:escaped_metadata) do
          <<~'EXPECTED'
            Page URL:    http://example.com/\x07
            Title:       猫のイラスト\x1B[2J
            Description: かわいい猫\x0D\x0A説明\x09\x9B31m\x7F
            Image URL:   http://example.com/test.png
          EXPECTED
        end

        it 'escapes controls in image URLs when stdout is redirected' do
          allow(irasuto).to receive(:image_urls).and_return(["http://example.com/test.png\x7f"])
          expect(Net::HTTP).not_to receive(:start)
          expected_output = escaped_metadata.sub("test.png\n", "test.png\\x7F\n")

          expect do
            allow($stdout).to receive(:tty?).and_return(false)
            subject
          end.to output(expected_output).to_stdout
        end

        it 'escapes metadata controls while preserving Japanese text and renderer output' do
          allow(TerminalImage).to receive(:show) { print "\e[0m" }

          expect do
            allow($stdout).to receive(:tty?).and_return(true)
            subject
          end.to output(escaped_metadata + "\e[0m").to_stdout
        end
      end

      it 'renders each image at the byte limit and removes its temporary file' do
        rendered_images = []
        allow(TerminalImage).to receive(:show) { |file| rendered_images << file.read }
        expect do
          allow($stdout).to receive(:tty?).and_return(true)
          subject
        end.to output(expected).to_stdout
        expect(rendered_images).to eq(image_data)
        expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
      end

      it 'stops reading an oversized image without Content-Length and renders the next image' do
        oversized = Net::HTTPOK.new('1.1', '200', 'OK')
        allow(http).to receive(:request_get).with('/test.png').and_yield(oversized)
        allow(oversized).to receive(:read_body) do |&read_chunk|
          read_chunk.call(image_data.first)
          read_chunk.call('x')
          raise 'Download continued past the byte limit'
        end

        expect(TerminalImage).to receive(:show).once do |file|
          expect(file.read).to eq(image_data.last)
        end
        warning = "warn: Image preview exceeds the #{image_data.first.bytesize}-byte limit\n"
        expect do
          allow($stdout).to receive(:tty?).and_return(true)
          subject
        end.to output(expected + warning).to_stdout
        expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
      end

      it 'renders an image after a relative redirect without reading the redirect body' do
        redirect = Net::HTTPFound.new('1.1', '302', 'Found')
        redirect['location'] = '/redirected.png'
        allow(http).to receive(:request_get).with('/test.png').and_yield(redirect)
        expect(redirect).not_to receive(:read_body)
        expect(http).to receive(:request_get).with('/redirected.png').and_yield(responses.fetch('/test.png'))
        expect(TerminalImage).to receive(:show).twice

        expect do
          allow($stdout).to receive(:tty?).and_return(true)
          subject
        end.to output(expected).to_stdout
      end

      it 'removes the temporary file when downloading fails' do
        allow(http).to receive(:request_get).with('/test.png').and_raise(IOError, 'download failed')

        allow($stdout).to receive(:tty?).and_return(true)
        expect { subject }.to raise_error(IOError, 'download failed')
        expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
      end

      it 'removes the temporary file when rendering fails' do
        allow(TerminalImage).to receive(:show).and_raise(IOError, 'render failed')

        allow($stdout).to receive(:tty?).and_return(true)
        expect { subject }.to raise_error(IOError, 'render failed')
        expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
      end
    end

    describe '#random' do
      subject { runner.random }
      before { allow(Irasutoya::Irasuto).to receive(:random) { irasuto } }
      it_behaves_like 'a command displays irasuto'
    end

    describe '#search' do
      subject { runner.search('query') }

      let(:irasuto_link) do
        Irasutoya::IrasutoLink.new(title: 'title', show_url: 'http://example.com')
      end

      before do
        allow(Irasutoya::Irasuto).to receive(:search) { [irasuto_link] }
        allow(irasuto_link).to receive(:fetch_irasuto) { irasuto }
      end

      it_behaves_like 'a command displays irasuto'

      it 'displays each of the first three results before fetching the next page' do
        links = Array.new(4) { instance_double(Irasutoya::IrasutoLink) }
        allow(Irasutoya::Irasuto).to receive(:search).with(query: 'query').and_return(links)

        links.take(3).each do |link|
          result = instance_double(Irasutoya::Irasuto)
          expect(link).to receive(:fetch_irasuto).ordered.and_return(result)
          expect(runner).to receive(:display).with(result).ordered
        end

        expect(links.last).not_to receive(:fetch_irasuto)
        subject
      end

      it 'skips a missing detail result and continues to the next link' do
        missing_link = instance_double(Irasutoya::IrasutoLink, fetch_irasuto: nil)
        allow(Irasutoya::Irasuto).to receive(:search).and_return([missing_link, irasuto_link])

        expect { subject }.to output(expected).to_stdout
      end

      context 'when a preview fails' do # rubocop:disable Metrics/BlockLength
        let(:next_result) do
          Irasutoya::Irasuto.new(
            url: 'http://example.com/next',
            title: 'Next result',
            description: 'Another illustration',
            image_urls: ['http://example.com/next.png']
          )
        end

        before do
          next_link = instance_double(Irasutoya::IrasutoLink, fetch_irasuto: next_result)
          allow(Irasutoya::Irasuto).to receive(:search).and_return([irasuto_link, next_link])
          next_response = Net::HTTPOK.new('1.1', '200', 'OK')
          allow(next_response).to receive(:read_body).and_yield('next')
          allow(http).to receive(:request_get).with('/next.png').and_yield(next_response)
        end

        shared_examples 'a recoverable preview failure' do
          it 'warns, renders later previews in order, and removes the temporary files' do
            [image_data.last, 'next'].each do |data|
              expect(TerminalImage).to receive(:show).ordered { |file| expect(file.read).to eq(data) }
            end

            warning = "warn: Could not preview #{irasuto.image_urls.first}: #{message}\n"
            expect do
              allow($stdout).to receive(:tty?).and_return(true)
              subject
            end.to output(/#{Regexp.escape(expected + warning)}.*Title:       Next result/m).to_stdout

            expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
          end
        end

        context 'when an image download returns 404' do
          let(:message) { '404 "Not Found"' }

          before do
            missing = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
            allow(http).to receive(:request_get).with('/test.png').and_yield(missing)
          end

          include_examples 'a recoverable preview failure'
        end

        [TerminalImage::UnsupportedFormat, TerminalImage::UnsupportedTerminal].each do |error_class|
          context "when rendering raises #{error_class}" do
            let(:message) { 'preview failed' }

            before { expect(TerminalImage).to receive(:show).ordered.and_raise(error_class, message) }

            include_examples 'a recoverable preview failure'
          end
        end
      end

      context 'when a result page returns 404' do
        let(:missing_url) { 'http://example.com/missing' }
        let(:last_url) { 'http://example.com/last' }
        let(:message) { '404 Not Found' }

        before do
          missing_link = Irasutoya::IrasutoLink.new(title: 'missing', show_url: missing_url)
          last_link = Irasutoya::IrasutoLink.new(title: 'last', show_url: last_url)
          last_result = Irasutoya::Irasuto.new(
            url: last_url, title: 'last', description: 'description', image_urls: irasuto.image_urls
          )
          allow(Irasutoya::Irasuto).to receive(:search).and_return([irasuto_link, missing_link, last_link])
          allow(missing_link).to receive(:fetch_irasuto)
            .and_raise(OpenURI::HTTPError.new(message, nil))
          allow(last_link).to receive(:fetch_irasuto).and_return(last_result)
        end

        it 'displays successful results in order and reports the failed URL once' do
          last_output = expected.sub(irasuto.url, last_url).sub('Title:       title', 'Title:       last')
          expect { subject }.to output(expected + last_output).to_stdout
            .and output("warn: Could not fetch result page #{missing_url}: 404 Not Found\n").to_stderr
        end

        context 'when the failed URL and error message contain terminal controls' do
          let(:missing_url) { "http://example.com/missing\a" }
          let(:message) { "404 Not Found\e[2J\r\n" }

          it 'escapes the warning and displays later results' do
            warning = 'warn: Could not fetch result page http://example.com/missing\x07: 404 Not Found\x1B[2J\x0D\x0A'
            last_output = expected.sub(irasuto.url, last_url).sub('Title:       title', 'Title:       last')
            expect { subject }.to output(expected + last_output).to_stdout
              .and output(warning + "\n").to_stderr
          end
        end
      end
    end
  end
end
