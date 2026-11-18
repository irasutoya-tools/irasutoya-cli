# frozen_string_literal: true

require 'open3'

RSpec.describe 'CLI help' do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:run_help) do
    <<~RUBY
      $PROGRAM_NAME = './exe/irasutoya'
      load $PROGRAM_NAME
      abort 'Help loaded the scraper' if defined?(Irasutoya::Irasuto)
      abort 'Help loaded the image renderer' if defined?(TerminalImage)
    RUBY
  end

  it 'lists the commands without loading the scraper or image renderer' do
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', '-e', run_help, '--', 'help', chdir: root)

    expect(status.success?).to be(true), stderr
    expect(stdout).to include('Commands:', 'irasutoya download PAGE_URL', 'irasutoya random', 'irasutoya search {query}')
  end

  it 'describes search without loading the scraper or image renderer' do
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', '-e', run_help, '--', 'help', 'search', chdir: root)

    expect(status.success?).to be(true), stderr
    expect(stdout).to include('Usage:', 'irasutoya search {query}', 'Shows images from up to three result pages.')
  end
end
