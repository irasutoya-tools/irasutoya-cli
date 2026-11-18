# frozen_string_literal: true

RSpec.describe 'Installation instructions' do
  it 'documents the gemspec Ruby requirement beside the installation command' do
    readme = File.read(File.expand_path('../README.md', __dir__))
    gemspec = Gem::Specification.load(File.expand_path('../irasutoya-cli.gemspec', __dir__))
    installation = readme[/^## Installation\n(.*?)(?=^## |\z)/m, 1]
    prerequisite = /^Ruby (\d+(?:\.\d+)+) or newer is required\.\n\n```sh\n\$ gem install irasutoya-cli$/
    minimum = installation&.match(prerequisite)

    expect(minimum).not_to be_nil
    expect(Gem::Requirement.new(">= #{minimum[1]}")).to eq(gemspec.required_ruby_version)
  end
end
