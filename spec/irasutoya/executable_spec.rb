# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe 'irasutoya executable' do # rubocop:disable Metrics/BlockLength
  let(:executable) { File.expand_path('../../exe/irasutoya', __dir__) }

  it 'fails when search has no query' do
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, executable, 'search')

    expect(stderr).to include('search')
    expect(status.exitstatus).to be > 0
  end

  it 'fails when the command is unknown' do
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, executable, 'unknown-command')

    expect(stderr).to include('unknown-command')
    expect(status.exitstatus).to be > 0
  end

  describe 'download' do
    let(:page_url) { 'https://www.irasutoya.com/cat.html' }

    it 'fails when the output option is omitted' do
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, executable, 'download', page_url)

      expect(stdout).to be_empty
      expect(stderr).to include("No value provided for required options '--output'")
      expect(status.exitstatus).to eq(1)
    end

    it 'fails when the output option has no directory argument' do
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, executable, 'download', page_url, '--output')

      expect(stdout).to be_empty
      expect(stderr).to include("No value provided for option '--output'")
      expect(status.exitstatus).to eq(1)
    end
  end

  it 'succeeds when help is requested' do
    stdout, _stderr, status = Open3.capture3(RbConfig.ruby, executable, 'help')

    expect(stdout).to include('Commands:')
    expect(status).to be_success
  end

  it 'lists the commands in the tree' do
    stdout, _stderr, status = Open3.capture3(RbConfig.ruby, executable, 'tree')

    expect(status).to be_success
    expect(stdout).to include(/\bdownload\b/, /\brandom\b/, /\bsearch\b/)
  end

  describe 'redirected text output' do
    let(:run_with_fixture) do
      <<~'RUBY'
        require 'irasutoya/cli/illustration'

        page_url = 'https://www.irasutoya.com/cat.html'
        result = Irasutoya::Irasuto.new(
          url: page_url, title: 'Cat', description: 'A cat illustration',
          image_urls: ['https://example.com/cat.png']
        )
        link = Irasutoya::IrasutoLink.new(title: result.title, show_url: page_url)
        link.define_singleton_method(:fetch_irasuto) { result }
        illustration = Irasutoya::Cli::Illustration
        illustration.define_singleton_method(:search) { |query:| [link] }
        illustration.define_singleton_method(:random) { result }

        load ARGV.shift
        abort 'Loaded terminal_image' if defined?(TerminalImage)
        abort 'Loaded ChunkyPNG' if defined?(ChunkyPNG)
      RUBY
    end

    [%w[search cat], %w[random]].each do |args|
      it "prints metadata for #{args.first} without loading the preview renderer" do
        stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-e', run_with_fixture, '--', executable, *args)

        expect(status.success?).to be(true), stderr
        expect(stderr).to be_empty
        expect(stdout).to eq(<<~TEXT)
          Page URL:    https://www.irasutoya.com/cat.html
          Title:       Cat
          Description: A cat illustration
          Image URL:   https://example.com/cat.png
        TEXT
      end
    end
  end
end
