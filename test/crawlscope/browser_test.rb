# frozen_string_literal: true

require "test_helper"

class CrawlscopeBrowserTest < Minitest::Test
  Response = Data.define(:url, :headers)

  class FakeBrowser
    attr_reader :quit_called

    def quit
      @quit_called = true
    end
  end

  class FakeNetwork
    attr_reader :cleared, :idle_waits, :status

    def initialize(response:, status: 200)
      @response = response
      @status = status
      @cleared = []
      @idle_waits = []
    end

    def clear(scope)
      @cleared << scope
    end

    attr_reader :response

    def wait_for_idle(duration:, timeout:)
      @idle_waits << {duration: duration, timeout: timeout}
    end
  end

  class FakePage
    attr_reader :evaluations, :network, :visited_url

    def initialize(network:, body: "<html></html>", current_url: "", url: "")
      @network = network
      @body = body
      @current_url = current_url
      @url = url
      @evaluations = []
    end

    attr_reader :body

    attr_reader :current_url

    def evaluate(script)
      @evaluations << script
    end

    def go_to(url)
      @visited_url = url
    end

    attr_reader :url
  end

  def test_fetch_returns_rendered_page
    network = FakeNetwork.new(response: Response.new(url: "https://example.com/final", headers: {"content-type" => "text/html"}))
    page = FakePage.new(network: network, body: "<html><body>Hello</body></html>")
    browser = browser_with(page: page, scroll_page: false)

    result = browser.fetch("https://example.com/start")

    assert_equal "https://example.com/start", page.visited_url
    assert_equal [:traffic], network.cleared
    assert_equal "https://example.com/final", result.final_url
    assert_equal "https://example.com/final", result.normalized_final_url
    assert_equal 200, result.status
    assert result.html?
    assert_equal [], page.evaluations
  end

  def test_fetch_scrolls_when_enabled
    network = FakeNetwork.new(response: Response.new(url: "", headers: {}))
    page = FakePage.new(network: network, current_url: "https://example.com/current")
    browser = browser_with(page: page, scroll_page: true)

    result = browser.fetch("https://example.com/start")

    assert_equal "https://example.com/current", result.final_url
    assert_equal 3, page.evaluations.size
    assert_equal 4, network.idle_waits.size
  end

  def test_fetch_falls_back_to_page_url_and_original_url
    page_url_network = FakeNetwork.new(response: nil)
    page_url = FakePage.new(network: page_url_network, url: "https://example.com/page")
    page_url_result = browser_with(page: page_url).fetch("https://example.com/start")

    original_url_network = FakeNetwork.new(response: nil)
    original_url = FakePage.new(network: original_url_network)
    original_url_result = browser_with(page: original_url).fetch("https://example.com/start")

    assert_equal "https://example.com/page", page_url_result.final_url
    assert_equal "https://example.com/start", original_url_result.final_url
  end

  def test_fetch_returns_error_page_when_navigation_fails
    page = Object.new
    def page.network
      raise Timeout::Error, "browser failed"
    end

    result = browser_with(page: page).fetch("https://example.com/start")

    assert_equal "https://example.com/start", result.final_url
    assert_nil result.status
    assert_equal "Timeout::Error: browser failed", result.error
  end

  def test_fetch_reraises_programmer_errors
    page = Object.new
    def page.network
      raise NoMethodError, "bad call"
    end

    browser = browser_with(page: page)

    assert_raises(NoMethodError) { browser.fetch("https://example.com/start") }
  end

  def test_close_quits_browser
    fake_browser = FakeBrowser.new
    browser = browser_with(browser: fake_browser)

    browser.close

    assert fake_browser.quit_called
  end

  def test_close_allows_missing_browser
    browser = browser_with(browser: nil)

    assert_nil browser.close
  end

  private

  def browser_with(page: FakePage.new(network: FakeNetwork.new(response: nil)), browser: FakeBrowser.new, scroll_page: false)
    Crawlscope::Browser.allocate.tap do |instance|
      instance.instance_variable_set(:@base_url, "https://example.com")
      instance.instance_variable_set(:@timeout_seconds, 20)
      instance.instance_variable_set(:@network_idle_timeout_seconds, 5)
      instance.instance_variable_set(:@scroll_page, scroll_page)
      instance.instance_variable_set(:@browser, browser)
      instance.instance_variable_set(:@page, page)
    end
  end
end
