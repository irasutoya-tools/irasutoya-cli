# frozen_string_literal: true

require 'irasutoya'
require 'net/http'
require 'terminal_image'
require 'tmpdir'

RSpec.describe Irasutoya::Cli do # rubocop:disable Metrics/BlockLength
  it 'has a version number' do
    expect(Irasutoya::Cli::VERSION).not_to be nil
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
    let(:image_data) { "\x89PNG\r\n\x1a\n".b }
    let(:http) { instance_double(Net::HTTP) }
    let(:response) { Net::HTTPOK.new('1.1', '200', 'OK') }

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
      stub_const('Irasutoya::Cli::Runner::MAX_PREVIEW_BYTES', image_data.bytesize)
      allow(Net::HTTP).to receive(:start).with('example.com', 80, use_ssl: false, max_retries: 0).and_yield(http)
      allow(http).to receive(:request_get).and_yield(response)
      allow(response).to receive(:read_body).and_yield(image_data.byteslice(0, 4)).and_yield(image_data.byteslice(4..))
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

      it 'renders each image at the byte limit and removes its temporary file' do
        expect(TerminalImage).to receive(:show).exactly(irasuto.image_urls.size).times do |file|
          expect(file.read).to eq(image_data)
        end
        expect do
          allow($stdout).to receive(:tty?).and_return(true)
          subject
        end.to output(expected).to_stdout
        expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
      end

      it 'stops reading an oversized image without Content-Length and renders the next image' do
        oversized = Net::HTTPOK.new('1.1', '200', 'OK')
        allow(http).to receive(:request_get).with('/test.png').and_yield(oversized)
        allow(oversized).to receive(:read_body) do |&read_chunk|
          read_chunk.call(image_data)
          read_chunk.call('x')
          raise 'Download continued past the byte limit'
        end

        expect(TerminalImage).to receive(:show).once do |file|
          expect(file.read).to eq(image_data)
        end
        warning = "warn: Image preview exceeds the #{image_data.bytesize}-byte limit\n"
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
        expect(http).to receive(:request_get).with('/redirected.png').and_yield(response)
        expect(TerminalImage).to receive(:show).twice

        expect do
          allow($stdout).to receive(:tty?).and_return(true)
          subject
        end.to output(expected).to_stdout
      end

      it 'removes the temporary file when downloading fails' do
        allow(http).to receive(:request_get).and_raise(IOError, 'download failed')

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

      context 'when terminal image raises error' do
        before do
          allow(TerminalImage).to receive(:show).and_raise(TerminalImage::UnsupportedTerminal)
        end

        let(:warnings) do
          <<~WARNING
            warn: This terminal is not able to show images inline
            warn: Please use iTerm2 or terminal installed libsixel.
          WARNING
        end

        it 'prints warnings after the image information and removes the temporary file' do
          expect do
            allow($stdout).to receive(:tty?).and_return(true)
            subject
          end.to output(expected + warnings).to_stdout
          expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
        end
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

      context 'when a result page returns 404' do
        let(:missing_url) { 'http://example.com/missing' }
        let(:last_url) { 'http://example.com/last' }

        before do
          missing_link = Irasutoya::IrasutoLink.new(title: 'missing', show_url: missing_url)
          last_link = Irasutoya::IrasutoLink.new(title: 'last', show_url: last_url)
          last_result = Irasutoya::Irasuto.new(
            url: last_url, title: 'last', description: 'description', image_urls: irasuto.image_urls
          )
          allow(Irasutoya::Irasuto).to receive(:search).and_return([irasuto_link, missing_link, last_link])
          allow(missing_link).to receive(:fetch_irasuto)
            .and_raise(OpenURI::HTTPError.new('404 Not Found', nil))
          allow(last_link).to receive(:fetch_irasuto).and_return(last_result)
        end

        it 'displays successful results in order and reports the failed URL once' do
          last_output = expected.sub(irasuto.url, last_url).sub('Title:       title', 'Title:       last')
          expect { subject }.to output(expected + last_output).to_stdout
            .and output("warn: Could not fetch result page #{missing_url}: 404 Not Found\n").to_stderr
        end
      end
    end
  end
end
