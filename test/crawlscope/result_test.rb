# frozen_string_literal: true

require "test_helper"

class CrawlscopeResultTest < Minitest::Test
  def test_ok_when_result_has_warnings_only
    issues = Crawlscope::IssueCollection.new
    issues.add(code: :missing_title, severity: :warning, category: :metadata, url: "https://example.com", message: "missing <title>", details: {})

    result = result_with(issues)

    assert result.ok?
  end

  def test_not_ok_when_result_has_errors
    issues = Crawlscope::IssueCollection.new
    issues.add(code: :fetch_failed, severity: :error, category: :crawl, url: "https://example.com", message: "timeout", details: {})

    result = result_with(issues)

    refute result.ok?
  end

  private

  def result_with(issues)
    Crawlscope::Result.new(
      base_url: "https://example.com",
      sitemap_path: "/tmp/sitemap.xml",
      urls: ["https://example.com"],
      pages: [Object.new],
      issues: issues
    )
  end
end
