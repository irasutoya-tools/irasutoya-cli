# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Irasutoya::Cli do # rubocop:disable Metrics/BlockLength
  it 'has a version number' do
    expect(Irasutoya::Cli::VERSION).not_to be nil
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
      it 'should say image information' do
        expect { subject }.to output(expected).to_stdout
      end

      it 'renders each image at the byte limit and removes its temporary file' do
        expect(TerminalImage).to receive(:show).exactly(irasuto.image_urls.size).times do |file|
          expect(file.read).to eq(image_data)
        end
        expect { subject }.to output(expected).to_stdout
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
        expect { subject }.to output(expected + warning).to_stdout
        expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
      end

      it 'renders an image after a relative redirect without reading the redirect body' do
        redirect = Net::HTTPFound.new('1.1', '302', 'Found')
        redirect['location'] = '/redirected.png'
        allow(http).to receive(:request_get).with('/test.png').and_yield(redirect)
        expect(redirect).not_to receive(:read_body)
        expect(http).to receive(:request_get).with('/redirected.png').and_yield(response)
        expect(TerminalImage).to receive(:show).twice

        expect { subject }.to output(expected).to_stdout
      end

      it 'removes the temporary file when downloading fails' do
        allow(http).to receive(:request_get).and_raise(IOError, 'download failed')

        expect { subject }.to raise_error(IOError, 'download failed')
        expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
      end

      it 'removes the temporary file when rendering fails' do
        allow(TerminalImage).to receive(:show).and_raise(IOError, 'render failed')

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

        it 'should say' do
          expect { subject }.to output(expected + warnings).to_stdout
          expect(Dir.children(ENV.fetch('TMPDIR'))).to be_empty
        end
      end
    end

    describe '#random' do
      subject { Irasutoya::Cli::Runner.new.random }
      before { allow(Irasutoya::Irasuto).to receive(:random) { irasuto } }
      it_behaves_like 'a command displays irasuto'
    end

    describe '#search' do
      subject { Irasutoya::Cli::Runner.new.search('query') }

      let(:irasuto_link) do
        Irasutoya::IrasutoLink.new(title: 'title', show_url: 'http://example.com')
      end

      before do
        allow(Irasutoya::Irasuto).to receive(:search) { [irasuto_link] }
        allow(irasuto_link).to receive(:fetch_irasuto) { irasuto }
      end

      it_behaves_like 'a command displays irasuto'
    end
  end
end
