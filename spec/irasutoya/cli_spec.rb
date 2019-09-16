# frozen_string_literal: true

RSpec.describe Irasutoya::Cli do
  it 'has a version number' do
    expect(Irasutoya::Cli::VERSION).not_to be nil
  end
end
