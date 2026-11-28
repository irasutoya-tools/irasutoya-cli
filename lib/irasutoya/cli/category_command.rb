# frozen_string_literal: true

require 'thor'
require 'irasutoya/cli/category'
require 'irasutoya/cli/terminal_output'

module Irasutoya
  module Cli
    class CategoryCommand
      def initialize(jsonl: false)
        @jsonl = jsonl
      end

      def list
        Category.all.each(&method(:display_category))
      end

      def browse(title)
        category = Category.find(title)
        raise Thor::Error, "Category not found: #{TerminalOutput.escape_controls(title)}" unless category

        category.fetch_irasuto_links
      end

      private

      def display_category(category)
        return display_category_jsonl(category) if @jsonl

        $stdout.puts TerminalOutput.escape_controls(category.title)
      end

      def display_category_jsonl(category)
        require 'json'

        $stdout.puts JSON.generate(title: category.title)
        $stdout.flush
      end
    end
  end
end
