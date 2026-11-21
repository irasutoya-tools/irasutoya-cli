# frozen_string_literal: true

require 'irasutoya'
require 'irasutoya/cli/illustration'
require 'irasutoya/cli/preview'
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

  it 'describes the search page limit and multiple images in help and the CLI reference' do
    description = 'Shows images from up to three result pages. Each page can contain multiple images.'
    reference = File.read(File.expand_path('../../docs/usage.md', __dir__))

    expect { Irasutoya::Cli::Runner.start(%w[help search]) }.to output(/#{Regexp.escape(description)}/).to_stdout
    expect(reference).to match(/up to three result pages, each of which can\s+contain multiple images/)
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
    let(:headers) { { 'Accept-Encoding' => 'identity' } }
    let(:http) { instance_double(Net::HTTP, finish: nil) }
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
      allow(Net::HTTP).to receive(:start).with('example.com', 443, use_ssl: true, max_retries: 0, ignore_eof: false).and_return(http)
      responses.each { |path, response| allow(http).to receive(:request_get).with(path, headers).and_yield(response) }
      allow(Irasutoya::Cli::Preview).to receive(:show)
    end

    shared_examples_for 'a command displays irasuto' do
      it 'prints metadata without downloading or rendering when stdout is redirected' do
        expect(Net::HTTP).not_to receive(:start)
        expect(Irasutoya::Cli::Preview).not_to receive(:show)

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
          allow(Irasutoya::Cli::Preview).to receive(:show) { print "\e[0m" }

          expect do
            allow($stdout).to receive(:tty?).and_return(true)
            subject
          end.to output(escaped_metadata + "\e[0m").to_stdout
        end
      end

      it 'renders each image at the byte limit and removes its temporary file' do
        rendered_images = []
        allow(Irasutoya::Cli::Preview).to receive(:show) { |file| rendered_images << file.read }
        expect do
          allow($stdout).to receive(:tty?).and_return(true)
          subject
        end.to output(expected).to_stdout
        expect(rendered_images).to eq(image_data)
        expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
      end

      it 'stops reading an oversized image without Content-Length and renders the next image' do
        oversized = Net::HTTPOK.new('1.1', '200', 'OK')
        allow(http).to receive(:request_get).with('/test.png', headers).and_yield(oversized)
        allow(oversized).to receive(:read_body) do |&read_chunk|
          read_chunk.call(image_data.first)
          read_chunk.call('x')
          raise 'Download continued past the byte limit'
        end

        expect(Irasutoya::Cli::Preview).to receive(:show).once do |file|
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
        redirect['content-length'] = '10'
        allow(http).to receive(:request_get).with('/test.png', headers).and_yield(redirect)
        expect(redirect).not_to receive(:read_body)
        expect(http).to receive(:request_get).with('/redirected.png', headers).and_yield(responses.fetch('/test.png'))
        expect(Net::HTTP).to receive(:start).twice.and_return(http)
        expect(http).to receive(:finish).twice
        expect(Irasutoya::Cli::Preview).to receive(:show).twice

        expect do
          allow($stdout).to receive(:tty?).and_return(true)
          subject
        end.to output(expected).to_stdout
      end

      it 'warns about an HTTP redirect and previews the next image without connecting to the redirect target' do
        redirect = Net::HTTPFound.new('1.1', '302', 'Found')
        redirect['location'] = 'http://other.example.com/image.png'
        allow(http).to receive(:request_get).with('/test.png', headers).and_yield(redirect)
        expect(Net::HTTP).to receive(:start).with('example.com', 443, use_ssl: true, max_retries: 0, ignore_eof: false).twice
        expect(Irasutoya::Cli::Preview).to receive(:show).once { |file| expect(file.read).to eq(image_data.last) }

        warning = "warn: Could not preview #{irasuto.image_urls.first}: Image redirect must use HTTPS\n"
        expect do
          allow($stdout).to receive(:tty?).and_return(true)
          subject
        end.to output(expected + warning).to_stdout
      end

      it 'removes the temporary file when downloading fails' do
        allow(http).to receive(:request_get).with('/test.png', headers).and_raise(IOError, 'download failed')

        allow($stdout).to receive(:tty?).and_return(true)
        expect { subject }.to raise_error(IOError, 'download failed')
        expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
      end

      it 'removes the temporary file when rendering fails' do
        allow(Irasutoya::Cli::Preview).to receive(:show).and_raise(IOError, 'render failed')

        allow($stdout).to receive(:tty?).and_return(true)
        expect { subject }.to raise_error(IOError, 'render failed')
        expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
      end
    end

    describe '#random' do
      subject { runner.random }
      before { allow(Irasutoya::Cli::Illustration).to receive(:random) { irasuto } }
      it_behaves_like 'a command displays irasuto'

      it 'upgrades the page URL returned by the random feed before fetching it' do
        illustration = Irasutoya::Cli::Illustration
        allow(illustration).to receive(:random).and_call_original
        allow(illustration).to receive(:random_url).and_return('http://www.irasutoya.com/cat.html')
        uri = URI.parse('https://www.irasutoya.com/cat.html')
        expect(OpenURI).to receive(:open_http).with(anything, uri, anything, anything) do |buffer|
          buffer << '<div class="entry"><img src="http://example.com/cat.png"></div>'
          buffer.io.rewind
        end

        allow($stdout).to receive(:tty?).and_return(false)
        expect { subject }.to output(/Image URL:   http:\/\/example.com\/cat.png/).to_stdout
      end
    end

    describe '#search' do
      subject { runner.search('query') }

      let(:irasuto_link) do
        Irasutoya::IrasutoLink.new(title: 'title', show_url: 'https://example.com')
      end

      before do
        allow(Irasutoya::Irasuto).to receive(:search) { [irasuto_link] }
        allow(irasuto_link).to receive(:fetch_irasuto) { irasuto }
      end

      it_behaves_like 'a command displays irasuto'

      it 'upgrades a result page URL before fetching it' do
        legacy_link = Irasutoya::IrasutoLink.new(title: 'title', show_url: 'http://example.com')
        allow(Irasutoya::Irasuto).to receive(:search).and_return([legacy_link])
        expect(legacy_link).not_to receive(:fetch_irasuto)
        expect(Irasutoya::IrasutoLink).to receive(:new)
          .with(title: 'title', show_url: 'https://example.com').and_return(irasuto_link)

        expect { subject }.to output(expected).to_stdout
      end

      it 'displays each of the first three results before fetching the next page' do
        links = Array.new(4) { instance_double(Irasutoya::IrasutoLink, show_url: 'https://example.com') }
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
        missing_link = instance_double(Irasutoya::IrasutoLink, show_url: 'https://example.com', fetch_irasuto: nil)
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
          next_link = instance_double(Irasutoya::IrasutoLink, show_url: 'https://example.com/next', fetch_irasuto: next_result)
          allow(Irasutoya::Irasuto).to receive(:search).and_return([irasuto_link, next_link])
          next_response = Net::HTTPOK.new('1.1', '200', 'OK')
          allow(next_response).to receive(:read_body).and_yield('next')
          allow(http).to receive(:request_get).with('/next.png', headers).and_yield(next_response)
        end

        shared_examples 'a recoverable preview failure' do
          it 'warns, renders later previews in order, and removes the temporary files' do
            [image_data.last, 'next'].each do |data|
              expect(Irasutoya::Cli::Preview).to receive(:show).ordered { |file| expect(file.read).to eq(data) }
            end

            warning = "warn: Could not preview #{irasuto.image_urls.first}: #{message}\n"
            next_output = <<~EXPECTED
              Page URL:    #{next_result.url}
              Title:       #{next_result.title}
              Description: #{next_result.description}
              Image URL:   #{next_result.image_urls.first}
            EXPECTED
            expect do
              allow($stdout).to receive(:tty?).and_return(true)
              subject
            end.to output(expected + warning + next_output).to_stdout

            expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
          end
        end

        context 'when an image download returns 404' do
          let(:message) { '404 "Not Found"' }

          before do
            missing = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
            allow(http).to receive(:request_get).with('/test.png', headers).and_yield(missing)
          end

          include_examples 'a recoverable preview failure'
        end

        context 'when an image download returns partial content' do
          let(:message) { 'HTTP 206 Partial Content' }

          before do
            partial = Net::HTTPPartialContent.new('1.1', '206', 'Partial Content')
            allow(http).to receive(:request_get).with('/test.png', headers).and_yield(partial)
            expect(partial).not_to receive(:read_body)
          end

          include_examples 'a recoverable preview failure'
        end

        context 'when reading the first image body times out' do
          let(:timeout) { Net::ReadTimeout.new }
          let(:message) { timeout.message }

          before do
            allow(responses.fetch('/test.png')).to receive(:read_body) do |&read_chunk|
              read_chunk.call('pa')
              raise timeout
            end
          end

          include_examples 'a recoverable preview failure'
        end

        [TerminalImage::UnsupportedFormat, TerminalImage::UnsupportedTerminal].each do |error_class|
          context "when rendering raises #{error_class}" do
            let(:message) { 'preview failed' }

            before { expect(Irasutoya::Cli::Preview).to receive(:show).ordered.and_raise(error_class, message) }

            include_examples 'a recoverable preview failure'
          end
        end
      end

      shared_examples 'a recoverable detail page failure' do
        let(:missing_url) { 'https://example.com/missing' }
        let(:last_url) { 'https://example.com/last' }
        let(:warning) { "warn: Could not fetch result page #{missing_url}: #{detail_error.message}" }

        before do
          missing_link = Irasutoya::IrasutoLink.new(title: 'missing', show_url: missing_url)
          last_link = Irasutoya::IrasutoLink.new(title: 'last', show_url: last_url)
          last_result = Irasutoya::Irasuto.new(
            url: last_url, title: 'last', description: 'description', image_urls: irasuto.image_urls
          )
          allow(Irasutoya::Irasuto).to receive(:search).and_return([irasuto_link, missing_link, last_link])
          allow(missing_link).to receive(:fetch_irasuto).and_raise(detail_error)
          allow(last_link).to receive(:fetch_irasuto).and_return(last_result)
        end

        it 'displays successful results in order and reports the failed URL once' do
          last_output = expected.sub(irasuto.url, last_url).sub('Title:       title', 'Title:       last')
          expect { subject }.to output(expected + last_output).to_stdout
            .and output(warning + "\n").to_stderr
        end
      end

      context 'when a result page returns 404' do
        let(:detail_error) { OpenURI::HTTPError.new('404 Not Found', nil) }

        it_behaves_like 'a recoverable detail page failure'
      end

      context 'when the error message contains terminal controls' do
        it_behaves_like 'a recoverable detail page failure' do
          let(:detail_error) { OpenURI::HTTPError.new("404 Not Found\e[2J\r\n", nil) }
          let(:warning) { 'warn: Could not fetch result page https://example.com/missing: 404 Not Found\x1B[2J\x0D\x0A' }
        end
      end

      context 'when the result URL contains terminal controls' do
        it_behaves_like 'a recoverable detail page failure' do
          let(:missing_url) { "https://example.com/missing\a" }
          let(:detail_error) { URI::InvalidURIError.new }
          let(:parse_error) do
            Irasutoya::Cli::HttpsUrl.parse(missing_url)
          rescue URI::InvalidURIError => e
            e.message
          end
          let(:warning) { "warn: Could not fetch result page https://example.com/missing\\x07: #{parse_error}" }
        end
      end

      context 'when reading a result page times out' do
        let(:detail_error) { Net::ReadTimeout.new }

        it_behaves_like 'a recoverable detail page failure'
      end
    end
  end
end
