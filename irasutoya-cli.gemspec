# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'irasutoya/cli/version'

Gem::Specification.new do |spec|
  spec.name                              = 'irasutoya-cli'
  spec.version                           = Irasutoya::Cli::VERSION
  spec.required_ruby_version             = '>= 2.5'
  spec.authors                           = ['Yuji Ueki']
  spec.email                             = ['unhappychoice@gmail.com']
  spec.summary                           = 'CLI tool for irasutoya'
  spec.description                       = 'CLI tool for irasutoya'
  spec.homepage                          = 'https://github.com/unhappychoice/irasutoya-cli'
  spec.license                           = 'MIT'
  spec.metadata['homepage_uri']          = spec.homepage
  spec.metadata['source_code_uri']       = 'https://github.com/unhappychoice/irasutoya-cli'
  spec.metadata['changelog_uri']         = 'https://github.com/unhappychoice/irasutoya-cli'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'irasutoya'
  spec.add_dependency 'terminal_image'
  spec.add_dependency 'thor'

  spec.add_development_dependency 'base64'
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'codecov'
  spec.add_development_dependency 'guard'
  spec.add_development_dependency 'guard-rspec'
  spec.add_development_dependency 'guard-rubocop'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'simplecov'
end
