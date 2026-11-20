# frozen_string_literal: true

require 'irasutoya'
require 'json'
require 'irasutoya/cli/preview'

RSpec.describe 'JSON Lines output' do
  let(:runner) { Irasutoya::Cli::Runner }
  let(:result) do
    {
      'page_url' => 'https://www.irasutoya.com/2026/01/cat.html',
      'title' => '白い猫',
      'description' => "猫のイラスト\n別のポーズ",
      'image_urls' => %w[https://example.com/cat.png https://example.com/cat2.png]
    }
  end
  let(:illustration) do
    Irasutoya::Irasuto.new(
      url: result.fetch('page_url'), title: result.fetch('title'),
      description: result.fetch('description'), image_urls: result.fetch('image_urls')
    )
  end
  let(:link) { instance_double(Irasutoya::IrasutoLink, fetch_irasuto: illustration) }

  it 'prints one line with Japanese metadata and all image URLs for random, even in a terminal' do
    allow(Irasutoya::Irasuto).to receive(:random).and_return(illustration)
    expect(Irasutoya::Cli::Preview).not_to receive(:show)

    expect do
      allow($stdout).to receive(:tty?).and_return(true)
      runner.start(%w[random --jsonl])
    end.to output(satisfy { |stdout| stdout.lines.map { |line| JSON.parse(line) } == [result] })
      .to_stdout.and output('').to_stderr
  end

  it 'prints nothing when search has no results' do
    allow(Irasutoya::Irasuto).to receive(:search).with(query: 'missing').and_return([])

    expect { runner.start(%w[search missing --jsonl]) }.to output('').to_stdout.and output('').to_stderr
  end

  it 'warns on stderr and emits each successful result on its own line as search pages are fetched' do
    missing_url = 'https://www.irasutoya.com/2026/01/missing.html'
    missing = instance_double(Irasutoya::IrasutoLink, show_url: missing_url)
    last = instance_double(Irasutoya::IrasutoLink)
    last_illustration = illustration.dup
    last_url = 'https://www.irasutoya.com/2026/01/another-cat.html'
    allow(last_illustration).to receive(:url).and_return(last_url)
    allow(Irasutoya::Irasuto).to receive(:search).with(query: '猫').and_return([link, missing, last])
    allow(missing).to receive(:fetch_irasuto) { raise Timeout::Error, 'timed out' }
    allow(last).to receive(:fetch_irasuto) do
      expect($stdout.string.lines.map { |line| JSON.parse(line) }).to eq([result])
      last_illustration
    end

    expected = [result, result.merge('page_url' => last_url)]
    expect { runner.start(%w[search 猫 --jsonl]) }
      .to output(satisfy { |stdout| stdout.lines.map { |line| JSON.parse(line) } == expected }).to_stdout
      .and output("warn: Could not fetch result page #{missing_url}: timed out\n").to_stderr
  end
end
