# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  require 'simplecov-cobertura'

  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
  SimpleCov.skip ['spec']
  SimpleCov.minimum_coverage line: 100
  SimpleCov.start
end

require 'bundler/setup'
require 'irasutoya/cli'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
