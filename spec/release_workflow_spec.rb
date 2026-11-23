# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'yaml'

RSpec.describe 'The release workflow' do
  let(:path) { File.expand_path('../.github/workflows/release.yaml', __dir__) }
  let(:workflow) { YAML.safe_load_file(path) }
  let(:steps) { workflow.fetch('jobs').fetch('push').fetch('steps') }
  let(:verification) { steps.find { |step| step['name'] == 'Verify release tag' }.fetch('run') }

  it 'triggers publishing only for version tag pushes' do
    expect(workflow.fetch('on')).to eq('push' => { 'tags' => ['v[0-9]*'] })
    expect(steps.fetch(-1).fetch('uses')).to start_with('rubygems/release-gem@')
    expect(steps.fetch(0).fetch('with')).to include('fetch-depth' => 0)
  end

  it 'accepts a tag matching the packaged gem version' do
    gemspec = Gem::Specification.load(File.expand_path('../irasutoya-cli.gemspec', __dir__))
    output, status = verify_tag("v#{gemspec.version}")

    expect(status).to be_success, output
  end

  it 'rejects a mismatched tag before publishing' do
    output, status = verify_tag('v0.0.0')

    expect(status).not_to be_success
    expect(output).to include('must match the stable gem version')
  end

  it 'pins all external actions to full commit SHAs' do
    references = workflow.fetch('jobs').values.flat_map do |job|
      job.fetch('steps', []).filter_map { |step| step['uses'] }
    end
    external_actions = references.reject { |reference| reference.start_with?('./', 'docker://') }

    expect(external_actions).not_to be_empty
    expect(external_actions).to all(match(/\A[^@]+@[0-9a-f]{40}\z/))
  end

  def verify_tag(tag)
    ruby_path = [File.dirname(RbConfig.ruby), ENV.fetch('PATH')].join(File::PATH_SEPARATOR)
    Open3.capture2e(
      { 'GITHUB_REF_NAME' => tag, 'PATH' => ruby_path },
      'bash', '-e', '-c', verification, chdir: File.expand_path('..', __dir__)
    )
  end
end
