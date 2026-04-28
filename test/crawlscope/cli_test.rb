# frozen_string_literal: true

require "test_helper"

class CrawlscopeCliTest < Minitest::Test
  class FakeConfiguration
    attr_accessor :base_url, :concurrency, :network_idle_timeout_seconds, :output, :renderer, :timeout_seconds

    def initialize
      @base_url = nil
      @concurrency = 10
      @network_idle_timeout_seconds = 5
      @renderer = :http
      @timeout_seconds = 20
    end

    def browser_concurrency
      4
    end
  end

  class FakeTask
    attr_reader :validate_arguments, :json_ld_arguments

    def validate(base_url:, sitemap_path:, rule_names:)
      @validate_arguments = {
        base_url: base_url,
        sitemap_path: sitemap_path,
        rule_names: rule_names
      }

      success_result
    end

    def validate_json_ld(urls:, debug:, renderer:, report_path:, summary:, timeout_seconds:)
      @json_ld_arguments = {
        urls: urls,
        debug: debug,
        renderer: renderer,
        report_path: report_path,
        summary: summary,
        timeout_seconds: timeout_seconds
      }

      success_result
    end

    private

    def success_result
      Struct.new(:ok?).new(true)
    end
  end

  class FailingTask < FakeTask
    private

    def success_result
      Struct.new(:ok?).new(false)
    end
  end

  class InvalidTask < FakeTask
    def validate(base_url:, sitemap_path:, rule_names:)
      raise Crawlscope::ValidationError, "No URLs found in sitemap: #{sitemap_path}"
    end
  end

  def test_version_prints_current_version
    out = StringIO.new
    err = StringIO.new

    status = Crawlscope::Cli.start(["version"], out: out, err: err)

    assert_equal 0, status
    assert_equal "#{Crawlscope::VERSION}\n", out.string
    assert_empty err.string
  end

  def test_unknown_command_returns_error
    out = StringIO.new
    err = StringIO.new

    status = Crawlscope::Cli.start(["unknown"], out: out, err: err)

    assert_equal 1, status
    assert_includes err.string, "Unknown command: unknown"
    assert_includes err.string, "crawlscope validate --url"
  end

  def test_validate_passes_arguments_to_task
    configuration = FakeConfiguration.new
    task = FakeTask.new
    out = StringIO.new
    err = StringIO.new

    status = Crawlscope::Cli.start(
      ["validate", "--url", "https://example.com", "--sitemap", "https://example.com/sitemap-pages.xml", "--rules", "metadata,links", "--renderer", "browser", "--timeout", "30", "--network-idle-timeout", "9", "--concurrency", "3"],
      out: out,
      err: err,
      configuration: configuration,
      task: task
    )

    assert_equal 0, status
    assert_equal(
      {
        base_url: "https://example.com",
        sitemap_path: "https://example.com/sitemap-pages.xml",
        rule_names: "metadata,links"
      },
      task.validate_arguments
    )
    assert_equal :browser, configuration.renderer
    assert_equal 30, configuration.timeout_seconds
    assert_equal 9, configuration.network_idle_timeout_seconds
    assert_equal 3, configuration.concurrency
    assert_same out, configuration.output
    assert_empty err.string
  end

  def test_ldjson_reads_urls_from_environment
    configuration = FakeConfiguration.new
    task = FakeTask.new
    out = StringIO.new
    err = StringIO.new

    with_env("URL" => "https://example.com/a; https://example.com/b", "SUMMARY" => "1", "DEBUG" => "1") do
      status = Crawlscope::Cli.start(["ldjson"], out: out, err: err, configuration: configuration, task: task)

      assert_equal 0, status
    end

    assert_equal(
      {
        urls: ["https://example.com/a", "https://example.com/b"],
        debug: true,
        renderer: :http,
        report_path: nil,
        summary: true,
        timeout_seconds: 20
      },
      task.json_ld_arguments
    )
    assert_same out, configuration.output
    assert_empty err.string
  end

  def test_ldjson_defaults_to_configured_base_url
    configuration = FakeConfiguration.new
    configuration.base_url = "https://example.com"
    task = FakeTask.new

    status = Crawlscope::Cli.start(["ldjson"], out: StringIO.new, err: StringIO.new, configuration: configuration, task: task)

    assert_equal 0, status
    assert_equal ["https://example.com"], task.json_ld_arguments[:urls]
  end

  def test_validate_caps_default_browser_concurrency
    configuration = FakeConfiguration.new
    task = FakeTask.new
    out = StringIO.new
    err = StringIO.new

    with_env("JS" => "1") do
      status = Crawlscope::Cli.start(["validate", "--url", "https://example.com"], out: out, err: err, configuration: configuration, task: task)

      assert_equal 0, status
    end

    assert_equal :browser, configuration.renderer
    assert_equal 4, configuration.concurrency
    assert_includes out.string, "Default JS concurrency capped at 4"
  end

  def test_validate_uses_url_environment_as_base_url_for_default_sitemap
    configuration = FakeConfiguration.new
    task = FakeTask.new

    with_env("URL" => "https://example.com") do
      status = Crawlscope::Cli.start(["validate"], out: StringIO.new, err: StringIO.new, configuration: configuration, task: task)

      assert_equal 0, status
    end

    assert_equal "https://example.com", task.validate_arguments[:base_url]
    assert_nil task.validate_arguments[:sitemap_path]
  end

  def test_validate_uses_sitemap_mode_when_sitemap_is_configured
    task = FakeTask.new

    with_env("URL" => "https://example.com", "SITEMAP" => "https://example.com/sitemap.xml") do
      status = Crawlscope::Cli.start(["validate"], out: StringIO.new, err: StringIO.new, configuration: FakeConfiguration.new, task: task)

      assert_equal 0, status
    end

    assert_equal "https://example.com", task.validate_arguments[:base_url]
    assert_equal "https://example.com/sitemap.xml", task.validate_arguments[:sitemap_path]
  end

  def test_ldjson_accepts_repeated_urls_and_options
    configuration = FakeConfiguration.new
    task = FakeTask.new
    out = StringIO.new
    err = StringIO.new

    status = Crawlscope::Cli.start(
      ["ldjson", "--url", "https://example.com/a", "--url", "https://example.com/b", "--renderer", "browser", "--timeout", "12", "--network-idle-timeout", "3", "--report-path", "report.json", "--debug", "--summary"],
      out: out,
      err: err,
      configuration: configuration,
      task: task
    )

    assert_equal 0, status
    assert_equal(
      {
        urls: ["https://example.com/a", "https://example.com/b"],
        debug: true,
        renderer: :browser,
        report_path: "report.json",
        summary: true,
        timeout_seconds: 12
      },
      task.json_ld_arguments
    )
    assert_equal 3, configuration.network_idle_timeout_seconds
  end

  def test_ldjson_defaults_to_localhost
    out = StringIO.new
    err = StringIO.new
    task = FakeTask.new

    status = Crawlscope::Cli.start(["ldjson"], out: out, err: err, configuration: FakeConfiguration.new, task: task)

    assert_equal 0, status
    assert_equal ["http://localhost:3000"], task.json_ld_arguments[:urls]
    assert_empty err.string
  end

  def test_invalid_integer_option_returns_error
    out = StringIO.new
    err = StringIO.new

    status = Crawlscope::Cli.start(["validate", "--timeout", "0"], out: out, err: err, configuration: FakeConfiguration.new, task: FakeTask.new)

    assert_equal 1, status
    assert_includes err.string, "timeout must be >= 1"
  end

  def test_failed_result_returns_failed_status
    status = Crawlscope::Cli.start(["validate"], out: StringIO.new, err: StringIO.new, configuration: FakeConfiguration.new, task: FailingTask.new)

    assert_equal 1, status
  end

  def test_validation_errors_return_failed_status_without_reraising
    err = StringIO.new

    status = Crawlscope::Cli.start(["validate"], out: StringIO.new, err: err, configuration: FakeConfiguration.new, task: InvalidTask.new)

    assert_equal 1, status
    assert_includes err.string, "No URLs found in sitemap"
  end

  private

  def with_env(overrides)
    original_values = overrides.to_h { |key, _value| [key, ENV[key]] }

    overrides.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end

    yield
  ensure
    original_values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
