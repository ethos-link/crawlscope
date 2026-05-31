# frozen_string_literal: true

module Crawlscope
  module RakeTasks
    module_function

    def validate(url: nil, sitemap_path: nil, rule_names: nil)
      run("validate", argv: validate_argv(url: url, sitemap_path: sitemap_path, rule_names: rule_names))
    end

    def ldjson(urls: nil)
      run("ldjson", argv: ldjson_argv(urls: urls))
    end

    def validate_rule(rule, url: nil, sitemap_path: nil)
      validate(url: url, sitemap_path: sitemap_path, rule_names: rule)
    end

    def run(command, argv: [])
      status = Cli.start([command, *argv], out: $stdout, err: $stderr)
      exit(status) unless status.zero?
    end

    def validate_argv(url:, sitemap_path:, rule_names:)
      [
        option_pair("--url", url),
        option_pair("--sitemap", sitemap_path),
        option_pair("--rules", rule_names)
      ].compact.flatten
    end

    def ldjson_argv(urls:)
      Array(urls).flat_map { |url| option_pair("--url", url) }.compact
    end

    def option_pair(name, value)
      value = value.to_s.strip
      return if value.empty?

      [name, value]
    end
  end
end
