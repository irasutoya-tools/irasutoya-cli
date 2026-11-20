# frozen_string_literal: true

require 'yaml'

RSpec.describe 'The test workflow' do
  let(:path) { File.expand_path('../.github/workflows/test.yml', __dir__) }
  let(:workflow) { YAML.safe_load_file(path) }
  let(:test_job) { workflow.fetch('jobs').fetch('test') }
  let(:upload_step) do
    test_job.fetch('steps').find { |step| step.fetch('uses', '').start_with?('codecov/codecov-action@') }
  end

  it 'uploads coverage using GitHub OIDC without a Codecov upload token' do
    expect(test_job.fetch('permissions')).to include('id-token' => 'write')
    expect(upload_step.fetch('with')).to include('use_oidc' => true, 'files' => 'coverage/coverage.xml')
    expect(upload_step.fetch('with')).not_to have_key('token')
    expect(File.read(path)).not_to include('CODECOV_TOKEN')
  end
end
