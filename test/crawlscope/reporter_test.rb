# frozen_string_literal: true

require "stringio"
require "test_helper"

class CrawlscopeReporterTest < Minitest::Test
  def test_reports_ok_result
    io = StringIO.new
    result = Crawlscope::Result.new(
      base_url: "https://example.com",
      sitemap_path: "/tmp/sitemap.xml",
      urls: ["https://example.com"],
      pages: [Object.new],
      issues: Crawlscope::IssueCollection.new
    )

    Crawlscope::Reporter.new(io: io).report(result)

    output = io.string

    assert_includes output, "Crawlscope validation"
    assert_includes output, "Status: OK"
    refute_includes output, "Status: FAILED"
  end

  def test_reports_failed_result_with_grouped_counts_and_offenses
    io = StringIO.new
    issues = Crawlscope::IssueCollection.new
    issues.add(code: :missing_title, severity: :warning, category: :metadata, url: "https://example.com/a", message: "missing <title>", details: {})
    issues.add(code: :broken_internal_link, severity: :notice, category: :links, url: "https://example.com/b", message: "broken internal link", details: {})
    result = Crawlscope::Result.new(
      base_url: "https://example.com",
      sitemap_path: "/tmp/sitemap.xml",
      urls: ["https://example.com/a", "https://example.com/b"],
      pages: [Object.new, Object.new],
      issues: issues
    )

    Crawlscope::Reporter.new(io: io).report(result)

    output = io.string

    assert_includes output, "Status: FAILED"
    assert_includes output, "Issues: 2"
    assert_includes output, "Severity:"
    assert_includes output, "notice: 1"
    assert_includes output, "warning: 1"
    assert_includes output, "Category:"
    assert_includes output, "links: 1"
    assert_includes output, "metadata: 1"
    assert_includes output, "  - [warning] missing_title https://example.com/a missing <title>"
    assert_includes output, "  - [notice] broken_internal_link https://example.com/b broken internal link"
  end
end
