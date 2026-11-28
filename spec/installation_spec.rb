# frozen_string_literal: true

RSpec.describe 'Installation instructions' do
  let(:readme) { File.read(File.expand_path('../README.md', __dir__)) }

  it 'documents the gemspec Ruby requirement beside the installation command' do
    gemspec = Gem::Specification.load(File.expand_path('../irasutoya-cli.gemspec', __dir__))
    installation = readme[/^## Installation\n(.*?)(?=^## |\z)/m, 1]
    prerequisite = /^Ruby (\d+(?:\.\d+)+) or newer is required\.\n\n```sh\n\$ gem install irasutoya-cli$/
    minimum = installation&.match(prerequisite)

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

RSpec.describe 'Getting started guide' do
  it 'runs the walkthrough download only after extracting a page URL' do
    guide = File.read(File.expand_path('../docs/getting-started.md', __dir__))
    commands = guide[/^### Chain search and download\n.*?^```sh\n(.*?)^```/m, 1]

    expect(commands).to include(<<~'SH')
      $ page_url=$(bundle exec exe/irasutoya search '猫' --jsonl | jq -ser '.[0].page_url // empty') &&
        bundle exec exe/irasutoya download "$page_url" --output ./images
    SH
  end
end
