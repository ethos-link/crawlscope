# frozen_string_literal: true

require "test_helper"

class CrawlscopeRakeTasksTest < Minitest::Test
  def setup
    @original_start = Crawlscope::Cli.method(:start)
  end

  def teardown
    singleton_class = class << Crawlscope::Cli; self; end
    original_start = @original_start
    singleton_class.define_method(:start) do |*args, **kwargs|
      original_start.call(*args, **kwargs)
    end
  end

  def test_validate_passes_rake_arguments_to_cli
    calls = capture_cli_calls

    Crawlscope::RakeTasks.validate(
      url: "http://localhost:3001",
      sitemap_path: "http://localhost:3001/sitemap.xml",
      rule_names: "metadata,links"
    )

    assert_equal(
      ["validate", "--url", "http://localhost:3001", "--sitemap", "http://localhost:3001/sitemap.xml", "--rules", "metadata,links"],
      calls.fetch(0).fetch(:argv)
    )
  end

  def test_validate_rule_passes_rule_and_rake_arguments_to_cli
    calls = capture_cli_calls

    Crawlscope::RakeTasks.validate_rule(
      "metadata",
      url: "http://localhost:3001",
      sitemap_path: "http://localhost:3001/sitemap.xml"
    )

    assert_equal(
      ["validate", "--url", "http://localhost:3001", "--sitemap", "http://localhost:3001/sitemap.xml", "--rules", "metadata"],
      calls.fetch(0).fetch(:argv)
    )
  end

  def test_ldjson_passes_rake_url_argument_to_cli
    calls = capture_cli_calls

    Crawlscope::RakeTasks.ldjson(urls: "http://localhost:3001/article")

    assert_equal(
      ["ldjson", "--url", "http://localhost:3001/article"],
      calls.fetch(0).fetch(:argv)
    )
  end

  private

  def capture_cli_calls
    calls = []
    singleton_class = class << Crawlscope::Cli; self; end
    singleton_class.define_method(:start) do |argv, **kwargs|
      calls << {argv: argv, kwargs: kwargs}
      0
    end
    calls
  end
end
