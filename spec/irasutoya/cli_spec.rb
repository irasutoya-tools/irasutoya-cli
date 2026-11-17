# frozen_string_literal: true

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

    before { allow(TerminalImage).to receive(:show_url) }

    shared_examples_for 'a command displays irasuto' do
      it 'should say image information' do
        expect { subject }.to output(expected).to_stdout
      end

      it 'should show image' do
        expect(TerminalImage).to receive(:show_url).with(irasuto.image_url)
        subject
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

      {
        'the download returns HTTP 404' => OpenURI::HTTPError.new('404 Not Found', nil),
        'the image format is unsupported' => TerminalImage::UnsupportedFormat.new('Unsupported image format')
      }.each do |failure, error|
        it "continues rendering previews and displaying results when #{failure}" do
          failed_url, next_url = irasuto.image_urls
          next_result = Irasutoya::Irasuto.new(
            url: 'http://example.com/next',
            title: 'Next result',
            description: 'Another illustration',
            image_urls: ['http://example.com/next.png']
          )
          next_link = instance_double(Irasutoya::IrasutoLink, fetch_irasuto: next_result)
          allow(Irasutoya::Irasuto).to receive(:search).and_return([irasuto_link, next_link])
          allow(TerminalImage).to receive(:show_url).with(failed_url).and_raise(error)

          warning = "warn: Could not preview #{failed_url}: #{error.message}\n"
          expect { subject }.to output(/#{Regexp.escape(expected + warning)}.*Title:       Next result/m).to_stdout
          expect(TerminalImage).to have_received(:show_url).with(next_url).ordered
          expect(TerminalImage).to have_received(:show_url).with(next_result.image_url).ordered
        end
      end
    end
  end
end
