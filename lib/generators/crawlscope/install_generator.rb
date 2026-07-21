# frozen_string_literal: true

require "rails/generators"

module Crawlscope
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Create a lazy-safe Crawlscope initializer and task loader"

      def create_initializer
        template "initializer.rb.tt", "config/initializers/crawlscope.rb"
      end

      def configure_rakefile
        rakefile = File.join(destination_root, "Rakefile")
        return unless File.exist?(rakefile)
        return if File.read(rakefile).include?('require "crawlscope/tasks"')

        inject_into_file "Rakefile", rakefile_setup, before: /^require_relative ["']config\/application["']/
      end

      private

      def rakefile_setup
        <<~RUBY
          crawlscope_tasks_requested = Rake.application.options.show_tasks ||
            ARGV.any? { |argument| ["-T", "--tasks"].include?(argument) }
          require "crawlscope/tasks" if crawlscope_tasks_requested ||
            ARGV.any? { |argument| argument.start_with?("crawlscope:") }

        RUBY
      end
    end
  end
end
