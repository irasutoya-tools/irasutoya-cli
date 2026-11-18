# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe 'irasutoya executable' do
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

  it 'succeeds when help is requested' do
    stdout, _stderr, status = Open3.capture3(RbConfig.ruby, executable, 'help')

    expect(stdout).to include('Commands:')
    expect(status).to be_success
  end
end
