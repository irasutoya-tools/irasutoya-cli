# frozen_string_literal: true

require 'irasutoya/cli/category_command'
require 'json'

RSpec.describe Irasutoya::Cli::CategoryCommand do
  let(:category) { instance_double(Irasutoya::Cli::Category, title: '正月') }

  describe '#list' do
    before { allow(Irasutoya::Cli::Category).to receive(:all).and_return([category]) }

    it 'prints each category title' do
      expect { described_class.new.list }.to output("正月\n").to_stdout
    end

    it 'escapes terminal controls in a category title' do
      allow(category).to receive(:title).and_return("猫\e[2J")

      expect { described_class.new.list }.to output("猫\\x1B[2J\n").to_stdout
    end

    it 'prints one JSON object per category with jsonl enabled' do
      expect { described_class.new(jsonl: true).list }.to output(%({"title":"正月"}\n)).to_stdout
    end
  end

  describe '#browse' do
    let(:links) { double('links') }

    it 'returns the matching category illustration links' do
      allow(Irasutoya::Cli::Category).to receive(:find).with('正月').and_return(category)
      allow(category).to receive(:fetch_irasuto_links).and_return(links)

      expect(described_class.new.browse('正月')).to eq(links)
    end

    it 'raises a Thor::Error naming the unmatched category' do
      allow(Irasutoya::Cli::Category).to receive(:find).with('missing').and_return(nil)

      expect { described_class.new.browse('missing') }.to raise_error(Thor::Error, 'Category not found: missing')
    end

    it 'escapes terminal controls in an unmatched category title' do
      allow(Irasutoya::Cli::Category).to receive(:find).with("猫\e[2J").and_return(nil)

      expect { described_class.new.browse("猫\e[2J") }
        .to raise_error(Thor::Error, 'Category not found: 猫\x1B[2J')
    end
  end
end
