# frozen_string_literal: true

RSpec.describe 'Installation instructions' do
  let(:readme) { File.read(File.expand_path('../README.md', __dir__)) }

  it 'documents the published gem Ruby requirement beside the installation command' do
    installation = readme[/^## Installation\n(.*?)(?=^## |\z)/m, 1]

    prerequisite = 'The RubyGems release (1.0.1) requires Ruby 3.1 or newer.'

    expect(installation).to include("#{prerequisite}\n\n```sh\n$ gem install irasutoya-cli\n")
  end

  it 'documents the checkout Ruby requirement from the current gemspec' do
    gemspec = Gem::Specification.load(File.expand_path('../irasutoya-cli.gemspec', __dir__))
    checkout = readme[/^## Download images from a checkout\n(.*?)(?=^## |\z)/m, 1]
    minimum = checkout.match(/^The checkout requires Ruby (\d+(?:\.\d+)+) or newer\./)

    expect(minimum).not_to be_nil
    expect(Gem::Requirement.new(">= #{minimum[1]}")).to eq(gemspec.required_ruby_version)
  end

  it 'limits the RubyGems quick start to commands supported by version 1.0.1' do
    quick_start = readme[/^## Quick Start\n(.*?)(?=^## |\z)/m, 1]
    commands = quick_start.scan(/(?:^\$ |`)(irasutoya [^\n`]+)/).flatten

    expect(commands).to contain_exactly("irasutoya search '猫'", 'irasutoya random', 'irasutoya help')
  end

  it 'sets up the checkout before running the download example' do
    checkout = readme[/^## Download images from a checkout\n(.*?)(?=^## |\z)/m, 1]
    commands = checkout.scan(/^\$ (.+)$/).flatten

    expect(commands).to eq([
      'git clone https://github.com/irasutoya-tools/irasutoya-cli.git',
      'cd irasutoya-cli',
      'bundle install',
      "bundle exec exe/irasutoya download 'PAGE_URL' --output ./images"
    ])
  end
end
