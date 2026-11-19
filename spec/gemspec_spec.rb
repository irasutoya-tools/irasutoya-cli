# frozen_string_literal: true

RSpec.describe 'Gem metadata' do
  subject(:gemspec) { Gem::Specification.load(File.expand_path('../irasutoya-cli.gemspec', __dir__)) }

  let(:repository_url) { 'https://github.com/irasutoya-tools/irasutoya-cli' }

  it 'links to the project homepage and source code' do
    expect(gemspec.homepage).to eq(repository_url)
    expect(gemspec.metadata).to include('homepage_uri' => repository_url, 'source_code_uri' => repository_url)
  end

  it 'omits the changelog link' do
    expect(gemspec.metadata).not_to have_key('changelog_uri')
  end

  it 'requires terminal_image 1.1.0 or later within the 1.x series at runtime' do
    expect(gemspec.runtime_dependencies).to include(Gem::Dependency.new('terminal_image', '~> 1.1'))
  end
end
