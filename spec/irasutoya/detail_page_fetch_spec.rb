# frozen_string_literal: true

require 'irasutoya'
require 'irasutoya/cli/detail_page_fetch'
require 'irasutoya/cli/download'
require 'irasutoya/cli/illustration'
require 'nokogiri'

RSpec.describe Irasutoya::Cli::DetailPageFetch do
  it 'leaves Irasutoya::IrasutoLink ancestors unchanged after loading the illustration and download implementations' do
    expect(Irasutoya::IrasutoLink.ancestors).not_to include(Irasutoya::Cli::DetailPageParser)
  end

  describe '.fetch' do
    let(:link) { Irasutoya::IrasutoLink.new(title: nil, show_url: 'https://www.irasutoya.com/cat.html') }
    let(:document) do
      Nokogiri::HTML(<<~HTML)
        <div class="entry">
          <img alt="placeholder">
          <img src="https://example.com/first.png">
          <img alt="placeholder">
          <img src="https://example.com/second.png">
        </div>
      HTML
    end

    before { allow(link).to receive(:fetch_page_and_parse).and_return(document) }

    it 'skips images without a source and preserves the order of the remaining images' do
      irasuto = described_class.fetch(link)

      expect(irasuto.image_urls).to eq(%w[https://example.com/first.png https://example.com/second.png])
    end

    it 'does not change Irasutoya::IrasutoLink ancestors for other instances' do
      described_class.fetch(link)

      expect(Irasutoya::IrasutoLink.ancestors).not_to include(Irasutoya::Cli::DetailPageParser)
      other_link = Irasutoya::IrasutoLink.new(title: nil, show_url: 'https://www.irasutoya.com/dog.html')
      expect(other_link.singleton_class.ancestors).not_to include(Irasutoya::Cli::DetailPageParser)
    end
  end
end
