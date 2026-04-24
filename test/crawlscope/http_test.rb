# frozen_string_literal: true

require "test_helper"

class CrawlscopeHttpTest < Minitest::Test
  def test_fetch_parses_html_response
    stub_request(:get, "https://example.com/page")
      .to_return(status: 200, headers: {"Content-Type" => "text/html"}, body: "<html><body>Hello</body></html>")

    page = Crawlscope::Http.new(base_url: "https://example.com", timeout_seconds: 2).fetch("https://example.com/page")

    assert_equal 200, page.status
    assert page.html?
    assert_equal "Hello", page.doc.at_css("body").text
  end

  def test_fetch_parses_responses_without_content_type_as_html
    stub_request(:get, "https://example.com/page")
      .to_return(status: 200, body: "<html><body>Hello</body></html>")

    page = Crawlscope::Http.new(base_url: "https://example.com", timeout_seconds: 2).fetch("https://example.com/page")

    assert page.html?
  end

  def test_fetch_leaves_non_html_response_unparsed
    stub_request(:get, "https://example.com/feed.xml")
      .to_return(status: 200, headers: {"content-type" => "application/xml"}, body: "<feed></feed>")

    page = Crawlscope::Http.new(base_url: "https://example.com", timeout_seconds: 2).fetch("https://example.com/feed.xml")

    assert_equal 200, page.status
    refute page.html?
    assert_equal "<feed></feed>", page.body
  end

  def test_fetch_returns_error_page_for_failed_requests
    stub_request(:get, "https://example.com/down").to_timeout

    page = Crawlscope::Http.new(base_url: "https://example.com", timeout_seconds: 2).fetch("https://example.com/down")

    assert_nil page.status
    assert_includes page.error, "Faraday::ConnectionFailed"
    assert_equal "https://example.com/down", page.final_url
  end

  def test_fetch_reraises_programmer_errors
    http = Crawlscope::Http.new(base_url: "https://example.com", timeout_seconds: 2)

    def http.connection
      raise NoMethodError, "bad call"
    end

    assert_raises(NoMethodError) { http.fetch("https://example.com/down") }
  end
end
