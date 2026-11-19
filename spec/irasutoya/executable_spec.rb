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
end
