# frozen_string_literal: true

RSpec.describe Irasutoya::Cli do # rubocop:disable Metrics/BlockLength
  it 'has a version number' do
    expect(Irasutoya::Cli::VERSION).not_to be nil
  end

  describe '#random' do # rubocop:disable Metrics/BlockLength
    let(:irasuto) do
      Irasutoya::Irasuto.new(
        url: 'http://example.com',
        title: 'title',
        description: 'description',
        image_url: 'http://example.com/test.png'
      )
    end

    let(:expected) do
      <<~EXPECTED
        Page URL:    #{irasuto.url}
        Title:       #{irasuto.title}
        Description: #{irasuto.description}
        Image URL:   #{irasuto.image_url}
      EXPECTED
    end

    before do
      allow(Irasutoya::Irasuto).to receive(:random) { irasuto }
      allow(TerminalImage).to receive(:show_url)
    end

    it 'should say image information' do
      expect { Irasutoya::Cli::Runner.new.random }.to output(expected).to_stdout
    end

    it 'should show image' do
      expect(TerminalImage).to receive(:show_url).with(irasuto.image_url)
      Irasutoya::Cli::Runner.new.random
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
        expect { Irasutoya::Cli::Runner.new.random }.to output(expected + warnings).to_stdout
      end
    end
  end
end
