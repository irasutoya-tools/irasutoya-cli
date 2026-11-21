# frozen_string_literal: true

require 'irasutoya/cli/illustration'
require 'irasutoya/cli/download'

RSpec.describe Irasutoya::Cli::HtmlPage do
  let(:host) { 'www.irasutoya.com' }
  let(:page_url) { "https://#{host}/cat.html" }
  let(:http) { instance_double(Net::HTTP) }
  let(:headers) { { 'Accept-Encoding' => 'identity' } }
  let(:detail) { '<div class="entry"><img src="https://example.com/cat.png"></div>' }
  let(:search_html) { %(<div class="box"><a href="#{page_url}"></a><a>Cat</a></div>) }

  before do
    stub_const('Irasutoya::Cli::HtmlPage::MAX_BYTES', 256)
    allow(Net::HTTP).to receive(:start).with(host, 443, use_ssl: true, max_retries: 0,
                                           ignore_eof: false).and_yield(http)
  end

  it 'parses a response at the byte limit using its declared charset' do
    html = '<title>猫</title>'.encode('Shift_JIS').b.ljust(256)
    response = respond('/cat.html')
    response['content-type'] = 'text/html; charset="Shift_JIS"'
    response['content-length'] = '256'
    allow(response).to receive(:read_body).and_yield(html[0, 10]).and_yield(html[10..])

    document = Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url)
    expect(document.at_css('title').text).to eq('猫')
  end

  it 'rejects an oversized search response before reading or parsing it' do
    response = respond('/search?q=cat')
    response['content-length'] = '257'
    expect(response).not_to receive(:read_body)
    expect(Nokogiri::HTML).not_to receive(:parse)

    expect { Irasutoya::Cli::Runner.new.search('cat') }
      .to raise_error(Thor::Error, 'HTML response exceeds the 256-byte limit')
  end

  it 'skips an oversized detail without a declared length and displays the next result' do
    list = search_html + search_html.sub('/cat.html', '/next.html')
    allow(respond('/search?q=cat')).to receive(:read_body).and_yield(list)
    stream_oversized_detail
    allow(respond('/next.html')).to receive(:read_body).and_yield(detail)

    expect { Irasutoya::Cli::Runner.new.search('cat') }
      .to output(/Page URL:    https:\/\/www\.irasutoya\.com\/next\.html/).to_stdout
      .and output("warn: Could not fetch result page #{page_url}: HTML response exceeds the 256-byte limit\n").to_stderr
  end

  it 'reports an oversized download page before parsing or transferring images' do
    stream_oversized_detail
    expect(Nokogiri::HTML).not_to receive(:parse)
    expect(Irasutoya::Cli::ImageTransfer).not_to receive(:fetch)

    expect { Irasutoya::Cli::Download.new(page_url, 'unused').save }
      .to raise_error(Thor::Error, "Could not fetch illustration page #{page_url}: HTML response exceeds the 256-byte limit")
  end

  it 'reports an oversized random illustration page' do
    allow(Irasutoya::Cli::Illustration).to receive(:random_url).and_return(page_url)
    stream_oversized_detail

    expect { Irasutoya::Cli::Runner.new.random }
      .to raise_error(Thor::Error, 'HTML response exceeds the 256-byte limit')
  end

  it 'does not read an error response body' do
    response = respond('/cat.html', Net::HTTPNotFound.new('1.1', '404', 'Not Found'))
    expect(response).not_to receive(:read_body)

    expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url) }
      .to raise_error(OpenURI::HTTPError, '404 Not Found')
  end

  it 'follows a relative redirect without reading its body' do
    redirect = respond('/cat.html', Net::HTTPFound.new('1.1', '302', 'Found'))
    redirect['location'] = 'next.html'
    expect(redirect).not_to receive(:read_body)
    allow(respond('/next.html')).to receive(:read_body).and_yield(detail)

    expect(Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url).at_css('img')['src'])
      .to eq('https://example.com/cat.png')
  end

  it 'stops after the redirect limit' do
    redirect = respond('/cat.html', Net::HTTPFound.new('1.1', '302', 'Found'))
    redirect['location'] = '/cat.html'
    expect(http).to receive(:request_get).with('/cat.html', headers).exactly(6).times.and_yield(redirect)

    expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url) }
      .to raise_error(described_class::Error, 'Too many HTML redirects')
  end

  it 'rejects malformed redirect destinations' do
    redirect = respond('/cat.html', Net::HTTPFound.new('1.1', '302', 'Found'))
    redirect['location'] = 'http://['

    expect { Irasutoya::Cli::Illustration.fetch_page_and_parse(page_url) }
      .to raise_error(described_class::Error, 'Invalid HTTPS redirect for HTML page')
  end

  def respond(path, response = Net::HTTPOK.new('1.1', '200', 'OK'))
    allow(http).to receive(:request_get).with(path, headers).and_yield(response)
    response
  end

  def stream_oversized_detail
    response = respond('/cat.html')
    response['transfer-encoding'] = 'chunked'
    expect(response).to receive(:read_body) do |&receive_chunk|
      receive_chunk.call(detail.ljust(256))
      receive_chunk.call('猫')
      raise 'Read continued after the HTML limit was exceeded'
    end
  end
end
