# frozen_string_literal: true

require 'cgi'
require 'irasutoya/cli/category'
require 'nokogiri'

RSpec.describe Irasutoya::Cli::Category do
  describe '.all' do
    let(:document) do
      Nokogiri::HTML(<<~HTML)
        <div id="sidebar-wrapper">
          <div class="widget">
            <h2>詳細カテゴリー</h2>
            <a href="https://www.irasutoya.com/search/label/#{CGI.escape('正月')}">正月</a>
            <a href="https://www.irasutoya.com/search/label/#{CGI.escape('動物')}">動物</a>
            <a href="https://www.irasutoya.com/about">About</a>
          </div>
          <div class="widget">
            <h2>Other widget</h2>
            <a href="https://www.irasutoya.com/search/label/ignored">Ignored</a>
          </div>
        </div>
      HTML
    end

    before { allow(described_class).to receive(:fetch_page_and_parse).and_return(document) }

    it 'returns categories scraped from the detailed category sidebar widget as the secure wrapper class' do
      categories = described_class.all

      expect(categories).to all(be_a(described_class))
      expect(categories.map(&:title)).to eq(%w[正月 動物])
    end
  end

  describe '.find' do
    let(:categories) do
      [described_class.new(title: '正月', list_url: 'https://www.irasutoya.com/search/label/a'),
       described_class.new(title: '動物', list_url: 'https://www.irasutoya.com/search/label/b')]
    end

    before { allow(described_class).to receive(:all).and_return(categories) }

    it 'returns the category with a matching title' do
      expect(described_class.find('動物')).to equal(categories.last)
    end

    it 'returns nil when no category title matches' do
      expect(described_class.find('missing')).to be_nil
    end
  end

  describe '#fetch_irasuto_links' do
    let(:category) do
      described_class.new(title: '正月', list_url: 'https://www.irasutoya.com/search/label/a')
    end
    let(:document) do
      Nokogiri::HTML(<<~HTML)
        <div class="box"><a href="https://www.irasutoya.com/a.html"></a><a>Title A</a></div>
        <div class="box"><a href="https://www.irasutoya.com/b.html"></a><a>Title B</a></div>
      HTML
    end

    before { allow(category).to receive(:fetch_page_and_parse).and_return(document) }

    it 'returns the illustration links listed on the category page' do
      links = category.fetch_irasuto_links

      expect(links.map(&:show_url)).to eq(%w[https://www.irasutoya.com/a.html https://www.irasutoya.com/b.html])
      expect(links.map(&:title)).to eq(['Title A', 'Title B'])
    end
  end
end
