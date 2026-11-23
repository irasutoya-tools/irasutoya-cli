# frozen_string_literal: true

require 'stringio'

RSpec.describe Irasutoya::Cli::ImageTransfer do
  let(:headers) { { 'Accept-Encoding' => 'identity' } }
  let(:http) { instance_double(Net::HTTP, started?: true, finish: nil) }
  let(:url) { URI('https://example.com/images/start.png') }

  before do
    allow(Net::HTTP).to receive(:start).with('example.com', 443, use_ssl: true, max_retries: 0, ignore_eof: false).and_return(http)
  end

  describe '.copy' do
    let(:image) { Net::HTTPOK.new('1.1', '200', 'OK') }
    let(:destination) { StringIO.new('prefix'.dup, 'ab') }

    before do
      allow(http).to receive(:request_get).with('/images/start.png', headers).and_yield(image)
    end

    it 'copies exactly the supplied number of bytes regardless of destination position' do
      image['Content-Length'] = '4'
      allow(image).to receive(:read_body).and_yield('é').and_yield('ab')

      described_class.copy(url, destination, max_bytes: 4)

      expect(destination.string).to eq('prefixéab'.b)
    end

    it 'stops before writing an overflowing chunk without Content-Length' do
      allow(image).to receive(:read_body) do |&receive_chunk|
        receive_chunk.call('é')
        receive_chunk.call('abc')
        raise 'Read past the byte limit'
      end

      expect do
        described_class.copy(url, destination, max_bytes: 4)
      end.to raise_error(described_class::SizeLimitExceededError)
      expect(destination.string).to eq('prefixé'.b)
    end
  end

  it 'resolves a relative redirect and yields only the successful response body' do
    redirect = redirect_to('next.png?size=large')
    image = Net::HTTPOK.new('1.1', '200', 'OK')
    expect(http).to receive(:request_get).with('/images/start.png', headers).ordered.and_yield(redirect)
    expect(redirect).not_to receive(:read_body)
    expect(http).to receive(:request_get).with('/images/next.png?size=large', headers).ordered.and_yield(image)
    allow(image).to receive(:read_body).and_yield('first').and_yield('second')

    expect { |chunks| described_class.fetch(url, &chunks) }.to yield_successive_args('first', 'second')
  end

  it 'yields the image after exactly five redirects' do
    paths = ['/images/start.png', *1.upto(5).map { |index| "/images/#{index}.png" }]
    paths.each_cons(2) do |source, target|
      expect(http).to receive(:request_get).with(source, headers).ordered.and_yield(redirect_to(target))
    end
    image = Net::HTTPOK.new('1.1', '200', 'OK')
    expect(http).to receive(:request_get).with(paths.last, headers).ordered.and_yield(image)
    allow(image).to receive(:read_body).and_yield('image')

    expect { |chunks| described_class.fetch(url, &chunks) }.to yield_with_args('image')
  end

  it 'shares the deadline between a redirect and the final response' do
    within_deadline = false
    expect(Timeout).to receive(:timeout)
      .with(described_class::TRANSFER_TIMEOUT, described_class::ResponseError, 'Image transfer deadline exceeded')
      .once do |*_, &transfer|
      within_deadline = true
      transfer.call
    ensure
      within_deadline = false
    end
    redirect = redirect_to('next.png')
    image = Net::HTTPOK.new('1.1', '200', 'OK')
    [['/images/start.png', redirect], ['/images/next.png', image]].each do |path, response|
      expect(http).to receive(:request_get).with(path, headers).ordered do |&receive_response|
        expect(within_deadline).to be(true)
        receive_response.call(response)
      end
    end
    allow(image).to receive(:read_body) do |&receive_chunk|
      expect(within_deadline).to be(true)
      receive_chunk.call('image')
    end
    expect { |chunks| described_class.fetch(url, &chunks) }.to yield_with_args('image')
  end

  it 'rejects a sixth redirect before requesting its destination' do
    paths = ['/images/start.png', *1.upto(6).map { |index| "/images/#{index}.png" }]
    paths.each_cons(2) do |source, target|
      expect(http).to receive(:request_get).with(source, headers).ordered.and_yield(redirect_to(target))
    end

    expect do
      described_class.fetch(url) { raise 'Unexpected image bytes' }
    end.to raise_error(Irasutoya::Cli::Error, 'Too many image redirects')
  end

  it 'reports an unsuccessful status without yielding its body' do
    missing = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
    allow(http).to receive(:request_get).with('/images/start.png', headers).and_yield(missing)

    expect do
      described_class.fetch(url) { raise 'Unexpected image bytes' }
    end.to raise_error(described_class::ResponseError, '404 "Not Found"')
  end

  it 'reports an unexpected EOF while reading a chunked body' do
    image = Net::HTTPOK.new('1.1', '200', 'OK')
    image['Transfer-Encoding'] = 'chunked'
    image['Content-Length'] = '12'
    expect(image).not_to receive(:content_length)
    allow(http).to receive(:request_get).with('/images/start.png', headers).and_yield(image)
    allow(image).to receive(:read_body).and_raise(EOFError, 'end of file reached')

    expect do
      described_class.fetch(url) { raise 'Unexpected image bytes' }
    end.to raise_error(described_class::IncompleteBodyError, 'end of file reached')
  end

  it 'rejects plaintext, non-HTTP, and hostless image URLs before making a request' do
    expect(Net::HTTP).not_to receive(:start)
    %w[http://example.com/image.png file:///image.png https:///image.png].each do |url|
      expect do
        described_class.fetch(URI(url)) { raise 'Unexpected image bytes' }
      end.to raise_error(described_class::InvalidSchemeError, 'Image URL must use HTTPS')
    end
  end

  it 'rejects redirects from HTTPS to HTTP before requesting the destination' do
    expect(http).to receive(:request_get).with('/images/start.png', headers)
      .and_yield(redirect_to('http://example.com/images/next.png'))
    expect do
      described_class.fetch(url) { raise 'Unexpected image bytes' }
    end.to raise_error(Irasutoya::Cli::Error, 'Image redirect must use HTTPS')
  end

  def redirect_to(location)
    Net::HTTPFound.new('1.1', '302', 'Found').tap { |response| response['location'] = location }
  end
end
