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

      context 'when terminal image raises error' do
        before do
          allow(TerminalImage).to receive(:show_url).and_raise(TerminalImage::UnsupportedTerminal)
        end

        let(:warnings) do
          <<~WARNING
            warn: This terminal is not able to show images inline
            warn: Please use iTerm2 or terminal installed libsixel.
          WARNING
        end

        it 'should say' do
          expect { subject }.to output(expected + warnings).to_stdout
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
