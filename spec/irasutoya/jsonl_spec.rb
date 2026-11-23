# frozen_string_literal: true

require 'irasutoya'
require 'irasutoya/cli/illustration'
require 'json'
require 'net/http'
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
  let(:link) { instance_double(Irasutoya::IrasutoLink, show_url: result.fetch('page_url'), fetch_irasuto: illustration) }

  it 'prints one line with Japanese metadata and all image URLs for random, even in a terminal' do
    allow(Irasutoya::Cli::Illustration).to receive(:random).and_return(illustration)
    expect(Irasutoya::Cli::Preview).not_to receive(:show)

    expect do
      allow($stdout).to receive(:tty?).and_return(true)
      runner.start(%w[random --jsonl])
    end.to output(satisfy { |stdout| stdout.lines.map { |line| JSON.parse(line) } == [result] })
      .to_stdout.and output('').to_stderr
  end

  it 'prints nothing when search has no results' do
    allow(Irasutoya::Cli::Illustration).to receive(:search).with(query: 'missing').and_return([])

    expect { runner.start(%w[search missing --jsonl]) }.to output('').to_stdout.and output('').to_stderr
  end

  it 'skips invalid search links and passes the emitted page URL to download' do
    invalid_urls = %w[https://example.com/cat.html https://www.irasutoya.com/cat]
    page_url = result.fetch('page_url')
    http = instance_double(Net::HTTP)
    expect(Net::HTTP).to receive(:start).with('www.irasutoya.com', 443, use_ssl: true, max_retries: 0,
                                             ignore_eof: false).exactly(3).times.and_yield(http)
    invalid_links = invalid_urls.map { |url| %(<div class="box"><a href="#{url}"></a><a>Invalid result</a></div>) }
    stub_html(http, '/search?q=%E7%8C%AB+%26+%E7%8A%AC', <<~HTML)
      #{invalid_links.join}
      <div class="box"><a href="#{page_url.sub('https:', 'http:')}"></a><a>Search title</a></div>
    HTML
    stub_html(http, URI.parse(page_url).request_uri, <<~HTML)
      <div class="post"><div class="title"><h2>白い猫</h2></div></div>
      <div class="entry">
        <div class="separator"><img src="//example.com/cat.png"><img src="https://example.com/cat2.png"></div>
        <div class="separator">猫のイラスト&#10;別のポーズ</div>
      </div>
    HTML

    records = nil
    expect { runner.start(['search', '猫 & 犬', '--jsonl']) }.to output(satisfy do |stdout|
      records = stdout.lines.map { |line| JSON.parse(line) }
      records == [result]
    end).to_stdout.and output(<<~WARNINGS).to_stderr
      warn: Could not fetch result page #{invalid_urls[0]}: Page URL must be on irasutoya.com or www.irasutoya.com with a path ending in .html
      warn: Could not fetch result page #{invalid_urls[1]}: Page URL must be on irasutoya.com or www.irasutoya.com with a path ending in .html
    WARNINGS

    stub_html(http, URI.parse(page_url).request_uri, '<div class="entry"></div>')
    expect do
      expect { runner.start(['download', records.first.fetch('page_url'), '--output', 'images']) }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("No images found on #{page_url}\n").to_stderr
  end

  it 'warns on stderr and emits each successful result on its own line as search pages are fetched' do
    missing_url = 'https://www.irasutoya.com/2026/01/missing.html'
    missing = instance_double(Irasutoya::IrasutoLink, show_url: missing_url)
    last_illustration = illustration.dup
    last_url = 'https://www.irasutoya.com/2026/01/another-cat.html'
    last = instance_double(Irasutoya::IrasutoLink, show_url: last_url)
    allow(last_illustration).to receive(:url).and_return(last_url)
    allow(Irasutoya::Cli::Illustration).to receive(:search).with(query: '猫').and_return([link, missing, last])
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

  def stub_html(http, path, html)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response['content-type'] = 'text/html; charset=UTF-8'
    allow(response).to receive(:read_body).and_yield(html.b)
    expect(http).to receive(:request_get).with(path, 'Accept-Encoding' => 'identity').and_yield(response)
  end
end
