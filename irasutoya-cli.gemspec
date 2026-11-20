# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'irasutoya/cli/version'

Gem::Specification.new do |spec|
  spec.name                              = 'irasutoya-cli'
  spec.version                           = Irasutoya::Cli::VERSION
  spec.required_ruby_version             = '>= 3.3'
  spec.authors                           = ['Yuji Ueki']
  spec.email                             = ['unhappychoice@gmail.com']
  spec.summary                           = 'CLI tool for irasutoya'
  spec.description                       = 'CLI tool for irasutoya'
  spec.homepage                          = 'https://github.com/irasutoya-tools/irasutoya-cli'
  spec.license                           = 'MIT'
  spec.metadata['homepage_uri']          = spec.homepage
  spec.metadata['source_code_uri']       = 'https://github.com/irasutoya-tools/irasutoya-cli'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.bindir = 'exe'
  spec.files = Dir.chdir(__dir__) do
    Dir.glob(['lib/**/*', "#{spec.bindir}/*"]).select { |path| File.file?(path) } +
      %w[README.md LICENSE.txt CODE_OF_CONDUCT.md images/example.png]
  end
  spec.executables   = spec.files.grep(%r{\A#{spec.bindir}/}) { |path| File.basename(path) }
  spec.require_paths = ['lib']

  spec.add_dependency 'irasutoya', '~> 2.0'
  spec.add_dependency 'json'
  spec.add_dependency 'terminal_image', '~> 1.1'
  spec.add_dependency 'thor'

  spec.add_development_dependency 'base64'
  spec.add_development_dependency 'bundler', '~> 4.1'
  spec.add_development_dependency 'guard'
  spec.add_development_dependency 'guard-rspec'
  spec.add_development_dependency 'guard-rubocop'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'simplecov-cobertura', '~> 4.0'
end
