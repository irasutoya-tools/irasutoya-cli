# frozen_string_literal: true

require 'irasutoya/cli/illustration'

RSpec.describe 'Random selection feed' do
  let(:runner) { Irasutoya::Cli::Runner }
  let(:http) { instance_double(Net::HTTP) }
  let(:feed) { Net::HTTPOK.new('1.1', '200', 'OK') }
  let(:headers) { { 'Accept-Encoding' => 'identity' } }
  let(:feed_url) { 'http://www.irasutoya.com/cat.html' }
  let(:page_url) { 'https://www.irasutoya.com/cat.html' }
  let(:feed_limit) { Irasutoya::Cli::Illustration::MAX_FEED_BYTES }
  let(:error_message) { "Random selection feed response exceeds the #{feed_limit}-byte limit\n" }

  before do
    allow(Net::HTTP).to receive(:start).with('www.irasutoya.com', 443, use_ssl: true, max_retries: 0,
                                           ignore_eof: false).and_return(http)
    allow(http).to receive(:started?).and_return(true)
    allow(http).to receive(:finish)
    expect(http).to receive(:request_get).with(
      '/feeds/posts/summary?start-index=1&max-results=1&alt=json-in-script', headers
    ).and_yield(feed)
  end

  it 'displays the selected illustration from a feed at the byte limit' do
    stub_successful_selection

    expect do
      allow($stdout).to receive(:tty?).and_return(false)
      runner.start(['random'])
    end.to output(/Page URL: +#{Regexp.escape(page_url)}/).to_stdout
  end

  it 'prints one JSON record with parsed metadata and ordered image URLs for the selected page' do
    stub_successful_selection
    expected = {
      'page_url' => page_url,
      'title' => '白い猫',
      'description' => "猫のイラスト\n別のポーズ",
      'image_urls' => %w[https://example.com/cat.png https://example.com/cat2.png]
    }

    expect { runner.start(%w[random --jsonl]) }
      .to output(satisfy { |stdout| stdout.lines.map { |line| JSON.parse(line) } == [expected] }).to_stdout
      .and output('').to_stderr
  end

  it 'selects index 1 without a second fetch when the random draw picks the first entry' do
    allow(Random).to receive(:rand).with(3).and_return(0)
    stub_successful_selection(count: 3)

    expect do
      allow($stdout).to receive(:tty?).and_return(false)
      runner.start(['random'])
    end.to output(/Page URL: +#{Regexp.escape(page_url)}/).to_stdout
  end

  it 'selects index N, never index 0, when the random draw picks the final entry' do
    allow(Random).to receive(:rand).with(3).and_return(2)
    stub_count_only(count: 3)
    stub_second_fetch(index: 3, feed_url: 'http://www.irasutoya.com/dog.html')

    expect do
      allow($stdout).to receive(:tty?).and_return(false)
      runner.start(['random'])
    end.to output(%r{Page URL: +https://www\.irasutoya\.com/dog\.html}).to_stdout
  end

  it 'rejects a declared oversized feed before reading its body' do
    feed['content-length'] = (feed_limit + 1).to_s
    expect(feed).not_to receive(:read_body)
    expect(JSON).not_to receive(:parse)

    expect_feed_failure(['random'])
  end

  it 'stops reading a chunked feed without Content-Length as soon as it crosses the limit' do
    feed['transfer-encoding'] = 'chunked'
    expect(http).to receive(:finish)
    expect(feed).to receive(:read_body) do |&read_chunk|
      read_chunk.call('a' * feed_limit)
      read_chunk.call('猫')
      raise 'Read continued past the feed byte limit'
    end
    expect(JSON).not_to receive(:parse)

    expect_feed_failure(%w[random --jsonl])
  end

  total_results_1 = '"openSearch$totalResults":{"$t":"1"}'

  {
    'an empty feed' => ["callback({\"feed\":{#{total_results_1},\"entry\":[]}});", 'has no usable entry'],
    'an invalid entry' => ["callback({\"feed\":{#{total_results_1},\"entry\":[null]}});", 'has no usable entry'],
    'invalid JSONP' => ['callback({"feed":{}}', 'is not valid JSONP'],
    'invalid JSON' => ['callback({"feed":});', 'contains invalid JSON'],
    'a missing alternate link' =>
      ["callback({\"feed\":{#{total_results_1},\"entry\":[{\"link\":[{\"rel\":\"self\"}]}]}});",
       'has no usable alternate link'],
    'an alternate link without an href' =>
      ["callback({\"feed\":{#{total_results_1},\"entry\":[{\"link\":[{\"rel\":\"alternate\"}]}]}});",
       'has no usable alternate link'],
    'a missing total result count' => ['callback({"feed":{"entry":[]}});', 'has no usable total result count'],
    'a non-numeric total result count' =>
      ['callback({"feed":{"openSearch$totalResults":{"$t":"many"},"entry":[]}});',
       'has no usable total result count']
  }.each do |description, (body, reason)|
    it "reports #{description}" do
      expect(feed).to receive(:read_body).and_yield(body)

      expect_feed_failure(%w[random --jsonl], "Random selection feed response #{reason}\n")
    end
  end

  it 'reports a feed with no entries at all' do
    expect(feed).to receive(:read_body).and_yield('callback({"feed":{"openSearch$totalResults":{"$t":"0"}}});')

    expect_feed_failure(%w[random --jsonl], "Random selection feed has no entries\n")
  end

  context 'when the feed returns HTTP 503' do
    let(:feed) { Net::HTTPServiceUnavailable.new('1.1', '503', 'Service Unavailable') }

    it 'reports the HTTP status without reading the response body' do
      expect(feed).not_to receive(:read_body)

      expect_feed_failure(%w[random --jsonl], "Random selection feed request failed (HTTP 503)\n")
    end
  end

  def stub_successful_selection(count: 1)
    jsonp = %({"feed":{"openSearch$totalResults":{"$t":"#{count}"},) +
            %("entry":[{"link":[{"rel":"self"},{"rel":"alternate","href":"#{feed_url}"}]}]}})
    body = "gdata.io.handleScriptLoaded(\n#{jsonp}\n);".ljust(feed_limit)
    feed['content-length'] = body.bytesize.to_s
    expect(feed).to receive(:read_body).and_yield(body[0, 32]).and_yield(body[32..])
    stub_detail_page('/cat.html', '//example.com/cat.png')
  end

  def stub_count_only(count:)
    body = %(gdata.io.handleScriptLoaded({"feed":{"openSearch$totalResults":{"$t":"#{count}"},"entry":[]}});)
    feed['content-length'] = body.bytesize.to_s
    expect(feed).to receive(:read_body).and_yield(body)
  end

  def stub_second_fetch(index:, feed_url:)
    jsonp = %({"feed":{"entry":[{"link":[{"rel":"alternate","href":"#{feed_url}"}]}]}})
    body = "gdata.io.handleScriptLoaded(#{jsonp});"
    second_feed = Net::HTTPOK.new('1.1', '200', 'OK')
    second_feed['content-length'] = body.bytesize.to_s
    expect(http).to receive(:request_get).with(
      "/feeds/posts/summary?start-index=#{index}&max-results=1&alt=json-in-script", headers
    ).and_yield(second_feed)
    expect(second_feed).to receive(:read_body).and_yield(body)
    stub_detail_page(feed_url.sub('http://www.irasutoya.com', ''), 'https://example.com/dog.png')
  end

  def stub_detail_page(path, image_url)
    page = Net::HTTPOK.new('1.1', '200', 'OK')
    page['content-type'] = 'text/html; charset=UTF-8'
    expect(http).to receive(:request_get).with(path, headers).and_yield(page)
    allow(page).to receive(:read_body).and_yield(<<~HTML.b)
      <div class="post"><div class="title"><h2>白い猫</h2></div></div>
      <div class="entry">
        <div class="separator">
          <img src="#{image_url}"><img data-src="placeholder.png"><img src="https://example.com/cat2.png">
        </div>
        <div class="separator">猫のイラスト&#10;別のポーズ</div>
      </div>
    HTML
  end

  def expect_feed_failure(args, message = error_message)
    expect(http).not_to receive(:request_get).with(/\.html/, headers)
    expect do
      expect { runner.start(args) }.to raise_error(SystemExit) { |error| expect(error.success?).to be false }
    end.to output(message).to_stderr.and output('').to_stdout
  end
end
