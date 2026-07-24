# frozen_string_literal: true

require "test_helper"

class CrawlscopeConfigurationTest < Minitest::Test
  def teardown
    Crawlscope.reset!
  end

  def test_audit_builds_from_configured_callables
    Crawlscope.configure do |config|
      config.base_url = -> { "https://example.com" }
      config.sitemap_path = -> { "/tmp/sitemap.xml" }
      config.site_name = -> { "Example" }
      config.concurrency = -> { 4 }
      config.fetch_executor = -> { :threaded }
      config.profile_token = -> { "profile-token" }
    end

    audit = Crawlscope.configuration.audit

    assert_equal "https://example.com", audit.instance_variable_get(:@base_url)
    assert_equal "/tmp/sitemap.xml", audit.instance_variable_get(:@sitemap_path)
    assert_equal 4, audit.instance_variable_get(:@concurrency)
    assert_equal :threaded, audit.instance_variable_get(:@fetch_executor)
    assert_equal "profile-token", audit.instance_variable_get(:@profile_token)
    assert_equal %i[
      indexability
      metadata
      structured_data
      uniqueness
      content_quality
      links
    ], audit.instance_variable_get(:@rules).map(&:code)
  end

  def test_audit_raises_without_base_url
    Crawlscope.configure do |config|
      config.sitemap_path = "/tmp/sitemap.xml"
    end

    error = assert_raises(Crawlscope::ConfigurationError) { Crawlscope.configuration.audit }

    assert_equal "Crawlscope base_url is not configured", error.message
  end

  def test_audit_raises_without_sitemap_path
    Crawlscope.configure do |config|
      config.base_url = "https://example.com"
    end

    error = assert_raises(Crawlscope::ConfigurationError) { Crawlscope.configuration.audit }

    assert_equal "Crawlscope sitemap_path is not configured", error.message
  end

  def test_defaults_are_normalized
    config = Crawlscope::Configuration.new

    assert_equal [200, 301, 302], config.allowed_statuses
    assert_equal 10, config.concurrency
    assert_equal :async, config.fetch_executor
    assert_equal 4, config.browser_concurrency
    assert_equal 5, config.network_idle_timeout_seconds
    assert_equal :http, config.renderer
    assert_equal 20, config.timeout_seconds
    assert_equal $stdout, config.output
    assert_nil config.profile_token
    assert config.scroll_page?
  end

  def test_browser_renderer_defaults_to_threaded_fetch_executor
    config = Crawlscope::Configuration.new
    config.renderer = :browser

    assert_equal :threaded, config.fetch_executor
  end

  def test_configured_values_are_normalized
    config = Crawlscope::Configuration.new
    config.allowed_statuses = ["200", "404"]
    config.concurrency = "2"
    config.fetch_executor = "async"
    config.network_idle_timeout_seconds = "7"
    config.renderer = "browser"
    config.timeout_seconds = "9"
    config.scroll_page = false

    assert_equal [200, 404], config.allowed_statuses
    assert_equal 2, config.concurrency
    assert_equal :async, config.fetch_executor
    assert_equal 2, config.browser_concurrency
    assert_equal 7, config.network_idle_timeout_seconds
    assert_equal :browser, config.renderer
    assert_equal 9, config.timeout_seconds
    refute config.scroll_page?
  end

  def test_renderer_must_be_supported
    config = Crawlscope::Configuration.new
    config.renderer = "webkit"

    error = assert_raises(Crawlscope::ConfigurationError) { config.renderer }

    assert_equal "Crawlscope renderer must be http or browser", error.message
  end

  def test_fetch_executor_must_be_supported
    config = Crawlscope::Configuration.new
    config.fetch_executor = "processes"

    error = assert_raises(Crawlscope::ConfigurationError) { config.fetch_executor }

    assert_equal "Crawlscope fetch_executor must be threaded or async", error.message
  end

  def test_numeric_values_must_be_positive_integers
    config = Crawlscope::Configuration.new
    config.concurrency = "0"

    error = assert_raises(Crawlscope::ConfigurationError) { config.concurrency }

    assert_equal "Crawlscope concurrency must be an integer >= 1", error.message
  end
end
