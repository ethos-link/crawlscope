# frozen_string_literal: true

module Crawlscope
  module RakeTasks
    module_function

    def validate
      run("validate")
    end

    def ldjson
      run("ldjson")
    end

    def validate_rule(rule)
      original_rules = ENV["RULES"]
      ENV["RULES"] = rule
      validate
    ensure
      ENV["RULES"] = original_rules
    end

    def run(command)
      status = Cli.start([command], out: $stdout, err: $stderr)
      exit(status) unless status.zero?
    end
  end
end
