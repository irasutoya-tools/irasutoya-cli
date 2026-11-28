# frozen_string_literal: true

RSpec.describe 'Published documentation links' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:repository_url) { 'https://github.com/irasutoya-tools/irasutoya-cli/blob/master/' }

  def link_targets(guide)
    File.read(File.join(root, 'docs', guide)).scan(/\]\(([^)]+)\)/).flatten
  end

  %w[usage.md troubleshooting.md].each do |guide|
    it "links to the checkout setup section from #{guide}" do
      expect(link_targets(guide)).to include("#{repository_url}README.md#download-images-from-a-checkout")
      expect(File.read(File.join(root, 'README.md'))).to include('## Download images from a checkout')
    end
  end

  it 'links to existing executable, source, and spec files from the architecture guide' do
    paths = link_targets('architecture.md').filter_map do |target|
      target.delete_prefix(repository_url) if target.start_with?(repository_url)
    end

    expect(paths).to include('exe/irasutoya', 'lib/irasutoya/cli.rb', 'spec/irasutoya/cli_spec.rb')
    paths.each { |path| expect(File.file?(File.join(root, path))).to be(true), "Missing repository file: #{path}" }
  end

  it 'keeps guide links relative and avoids parent-directory links' do
    Dir.glob(File.join(root, 'docs', '*.md')).each do |file|
      targets = link_targets(File.basename(file))
      expect(targets.grep(%r{\A\.\./})).to be_empty
    end

    expect(link_targets('usage.md')).to include('getting-started.md')
    expect(link_targets('troubleshooting.md')).to include('usage.md', 'usage.md#search-and-browse-illustrations')
  end
end
