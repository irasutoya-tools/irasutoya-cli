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

  describe 'redirected text output' do
    let(:run_with_fixture) do
      <<~'RUBY'
        require 'irasutoya/cli/illustration'

        module IllustrationFixture
          def random
            Irasutoya::Irasuto.new(
              url: 'https://www.irasutoya.com/cat.html', title: 'Cat',
              description: 'A cat', image_urls: ['https://example.com/cat.png']
            )
          end

          def search(query:)
            result = random
            link = Irasutoya::IrasutoLink.new(title: result.title, show_url: result.url)
            link.define_singleton_method(:fetch_irasuto) { result }
            [link]
          end
        end

        Irasutoya::Cli::Illustration.singleton_class.prepend(IllustrationFixture)
        load ARGV.shift
        abort 'Loaded terminal_image' if defined?(TerminalImage)
        abort 'Loaded ChunkyPNG' if defined?(ChunkyPNG)
      RUBY
    end

    [%w[search cat], %w[random]].each do |command|
      it "prints metadata for #{command.first} without loading preview dependencies" do
        stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-e', run_with_fixture, '--', executable, *command)

        expect(status.success?).to be(true), stderr
        expect(stderr).to be_empty
        expect(stdout).to eq(<<~EXPECTED)
          Page URL:    https://www.irasutoya.com/cat.html
          Title:       Cat
          Description: A cat
          Image URL:   https://example.com/cat.png
        EXPECTED
      end
    end
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
end
