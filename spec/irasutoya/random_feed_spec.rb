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
                                           ignore_eof: false).and_yield(http)
    expect(http).to receive(:request_get).with(
      %r{\A/feeds/posts/summary\?start-index=\d+&max-results=1&alt=json-in-script\z}, headers
    ).and_yield(feed)
  end

  it 'displays the selected illustration from a feed at the byte limit' do
    stub_successful_selection

    expect do
      allow($stdout).to receive(:tty?).and_return(false)
      runner.start(['random'])
    end.to output(/Page URL: +#{Regexp.escape(page_url)}/).to_stdout
  end

  it 'displays the normalized page URL in JSON Lines mode' do
    stub_successful_selection

    expect { runner.start(%w[random --jsonl]) }
      .to output(satisfy { |stdout| stdout.lines.one? && JSON.parse(stdout).fetch('page_url') == page_url }).to_stdout
  end

  it 'rejects a declared oversized feed before reading its body' do
    feed['content-length'] = (feed_limit + 1).to_s
    expect(feed).not_to receive(:read_body)

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

    expect_feed_failure(%w[random --jsonl])
  end

  def stub_successful_selection
    jsonp = %({"feed":{"entry":[{"link":[{"rel":"self"},{"rel":"alternate","href":"#{feed_url}"}]}]}})
    body = "callback(#{jsonp});".ljust(feed_limit)
    feed['content-length'] = body.bytesize.to_s
    expect(feed).to receive(:read_body).and_yield(body[0, 32]).and_yield(body[32..])
    page = Net::HTTPOK.new('1.1', '200', 'OK')
    expect(http).to receive(:request_get).with('/cat.html', headers).and_yield(page)
    allow(page).to receive(:read_body).and_yield(
      '<div class="entry"><img data-src="placeholder.png"><img src="https://example.com/cat.png"></div>'
    )
  end

  def expect_feed_failure(args)
    expect(JSON).not_to receive(:parse)
    expect(Irasutoya::Cli::Illustration).not_to receive(:fetch_page_and_parse)
    expect do
      expect { runner.start(args) }.to raise_error(SystemExit) { |error| expect(error.success?).to be false }
    end.to output(error_message).to_stderr.and output('').to_stdout
  end
end
