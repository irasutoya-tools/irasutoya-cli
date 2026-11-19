# frozen_string_literal: true

require 'yaml'

RSpec.describe 'The release workflow' do
  let(:path) { File.expand_path('../.github/workflows/release.yaml', __dir__) }
  let(:workflow) { YAML.safe_load_file(path) }

  it 'pins all external actions to full commit SHAs' do
    references = workflow.fetch('jobs').values.flat_map do |job|
      job.fetch('steps', []).filter_map { |step| step['uses'] }
    end
    external_actions = references.reject { |reference| reference.start_with?('./', 'docker://') }

    expect(external_actions).not_to be_empty
    expect(external_actions).to all(match(/\A[^@]+@[0-9a-f]{40}\z/))
  end
end
