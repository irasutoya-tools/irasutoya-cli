# frozen_string_literal: true

require 'fileutils'
require 'rubygems/package'
require 'tmpdir'

RSpec.describe 'The gem package' do
  it 'builds the same runtime package from a source archive without Git metadata' do
    root = File.expand_path('..', __dir__)
    gemspec = 'irasutoya-cli.gemspec'
    checkout = Gem::Specification.load(File.join(root, gemspec))

    Dir.mktmpdir do |source|
      paths = %w[lib exe images README.md LICENSE.txt CODE_OF_CONDUCT.md .github Guardfile .rubocop.yml Gemfile]
      FileUtils.cp_r(paths.push(gemspec).map { |path| File.join(root, path) }, source)
      archive = Gem::Specification.load(File.join(source, gemspec))
      package = Dir.chdir(source) do
        Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
          Gem::Package.new(File.join(source, Gem::Package.build(archive)))
        end
      end

      expect(package.contents).to match_array(checkout.files)
      expect(package.contents).to include('lib/irasutoya/cli.rb', 'exe/irasutoya', 'README.md', 'LICENSE.txt')
      expect(package.contents).not_to include('.github/workflows/test.yml', 'Guardfile', '.rubocop.yml', 'Gemfile')
      expect(package.spec.bindir).to eq('exe')
      expect(package.spec.executables).to eq(['irasutoya'])
      expect(package.spec.executables).to eq(checkout.executables)
    end
  end
end
