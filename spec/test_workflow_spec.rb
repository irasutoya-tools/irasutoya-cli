# frozen_string_literal: true

require 'yaml'

RSpec.describe 'The test workflow' do
  let(:path) { File.expand_path('../.github/workflows/test.yml', __dir__) }
  let(:workflow) { YAML.safe_load_file(path) }
  let(:test_job) { workflow.fetch('jobs').fetch('test') }
  let(:upload_step) do
    test_job.fetch('steps').find { |step| step.fetch('uses', '').start_with?('codecov/codecov-action@') }
  end

  it 'limits the default token permissions to reading repository contents' do
    expect(workflow.fetch('permissions')).to eq('contents' => 'read')
    expect(workflow.fetch('jobs').fetch('lint')).not_to have_key('permissions')
  end

  it 'caches Bundler dependencies in the lint and test jobs' do
    %w[lint test].each do |job_name|
      job = workflow.fetch('jobs').fetch(job_name)
      setup_step = job.fetch('steps').find { |step| step.fetch('uses', '').start_with?('ruby/setup-ruby@') }

      expect(setup_step.fetch('with')).to include('bundler-cache' => true)
    end
  end

  it 'pins ruby/setup-ruby to a full commit SHA annotated with its release version' do
    File.readlines(path).grep(%r{uses: ruby/setup-ruby@}).each do |line|
      expect(line).to match(%r{uses: ruby/setup-ruby@[0-9a-f]{40} # v\d+\.\d+\.\d+})
    end
  end

  it 'uploads coverage using GitHub OIDC without a Codecov upload token' do
    expect(test_job.fetch('permissions')).to eq('contents' => 'read', 'id-token' => 'write')
    expect(upload_step.fetch('with')).to include('use_oidc' => true, 'files' => 'coverage/coverage.xml')
    expect(upload_step.fetch('with')).not_to have_key('token')
    expect(File.read(path)).not_to include('CODECOV_TOKEN')
  end

  it 'builds the gem in the test matrix' do
    expect(test_job.fetch('steps')).to include(
      a_hash_including('run' => 'gem build irasutoya-cli.gemspec')
    )
  end
end
