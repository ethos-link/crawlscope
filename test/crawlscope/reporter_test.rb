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
      pages: [page],
      issues: Crawlscope::IssueCollection.new
    )

    Crawlscope::Reporter.new(io: io).report(result)

    output = io.string

    assert_includes output, "Crawlscope validation"
    assert_includes output, "Status: OK"
    refute_includes output, "Status: FAILED"
    refute_includes output, "Server Timing:"
  end

  def test_reports_warning_result_with_grouped_one_line_issues
    io = StringIO.new
    issues = Crawlscope::IssueCollection.new
    4.times do |index|
      issues.add(
        code: :low_dofollow_inlinks,
        severity: :warning,
        category: :links,
        url: "https://example.com/page-#{index + 1}",
        message: "dofollow inbound links 1 below 2",
        details: {
          dofollow_inbound_count: 1,
          minimum: 2,
          source_urls: ["https://example.com/source-#{index + 1}"]
        }
      )
    end
    issues.add(code: :missing_title, severity: :warning, category: :metadata, url: "https://example.com/a", message: "missing <title>", details: {})

    result = Crawlscope::Result.new(
      base_url: "https://example.com",
      sitemap_path: "/tmp/sitemap.xml",
      urls: ["https://example.com/a", "https://example.com/b"],
      pages: [page("/one"), page("/two")],
      issues: issues
    )

    Crawlscope::Reporter.new(io: io).report(result)

    output = io.string

    assert_includes output, "Status: WARNINGS"
    refute_includes output, "Status: FAILED"
    assert_includes output, "Issues: 5 total (5 warnings)"
    assert_includes output, "Summary:"
    assert_includes output, "links / low_dofollow_inlinks: 4"
    assert_includes output, "  - /page-1  inbound 1/2  sources: /source-1"
    assert_includes output, "  - /page-4  inbound 1/2  sources: /source-4"
    assert_includes output, "metadata / missing_title: 1"
    refute_includes output, "Severity:"
    refute_includes output, "Category:"
    refute_includes output, "... 1 more"
  end

  def test_reports_failed_status_when_errors_are_present
    io = StringIO.new
    issues = Crawlscope::IssueCollection.new
    issues.add(code: :fetch_failed, severity: :error, category: :crawl, url: "https://example.com/a", message: "timeout", details: {})
    issues.add(code: :missing_title, severity: :warning, category: :metadata, url: "https://example.com/a", message: "missing <title>", details: {})

    result = Crawlscope::Result.new(
      base_url: "https://example.com",
      sitemap_path: "/tmp/sitemap.xml",
      urls: ["https://example.com/a"],
      pages: [page],
      issues: issues
    )

    Crawlscope::Reporter.new(io: io).report(result)

    output = io.string

    assert_includes output, "Status: FAILED"
    assert_includes output, "Issues: 2 total (1 error, 1 warning)"
  end

  def test_limits_large_issue_groups
    io = StringIO.new
    issues = Crawlscope::IssueCollection.new
    21.times do |index|
      issues.add(
        code: :low_dofollow_inlinks,
        severity: :warning,
        category: :links,
        url: "https://example.com/page-#{index + 1}",
        message: "dofollow inbound links 1 below 2",
        details: {dofollow_inbound_count: 1, minimum: 2}
      )
    end

    result = Crawlscope::Result.new(
      base_url: "https://example.com",
      sitemap_path: "/tmp/sitemap.xml",
      urls: ["https://example.com"],
      pages: [page],
      issues: issues
    )

    Crawlscope::Reporter.new(io: io).report(result)

    output = io.string

    assert_includes output, "links / low_dofollow_inlinks: 21"
    assert_includes output, "  - /page-20  inbound 1/2"
    refute_includes output, "  - /page-21"
    assert_includes output, "  ... 1 more"
  end

  def test_reports_ratio_with_enough_precision_to_show_threshold_difference
    io = StringIO.new
    issues = Crawlscope::IssueCollection.new
    issues.add(
      code: :low_unique_token_ratio,
      severity: :warning,
      category: :content_quality,
      url: "https://example.com/a",
      message: "visible text has low token variety",
      details: {ratio: 0.249, threshold: 0.25}
    )

    result = Crawlscope::Result.new(
      base_url: "https://example.com",
      sitemap_path: "/tmp/sitemap.xml",
      urls: ["https://example.com/a"],
      pages: [page],
      issues: issues
    )

    Crawlscope::Reporter.new(io: io).report(result)

    assert_includes io.string, "ratio 0.249/0.250"
  end

  def test_reports_source_details_on_one_line
    io = StringIO.new
    issues = Crawlscope::IssueCollection.new
    4.times do |index|
      issues.add(
        code: :indexable_page_missing_from_sitemap,
        severity: :warning,
        category: :sitemaps,
        url: "https://example.com/overview-#{index + 1}",
        message: "indexable internal page is missing from sitemap",
        details: {source_url: "https://example.com/source-#{index + 1}"}
      )
    end

    result = Crawlscope::Result.new(
      base_url: "https://example.com",
      sitemap_path: "/tmp/sitemap.xml",
      urls: ["https://example.com"],
      pages: [page],
      issues: issues
    )

    Crawlscope::Reporter.new(io: io).report(result)

    output = io.string

    assert_includes output, "sitemaps / indexable_page_missing_from_sitemap: 4"
    assert_includes output, "  - /overview-1  indexable internal page is missing from sitemap  source: /source-1"
    assert_includes output, "  - /overview-4  indexable internal page is missing from sitemap  source: /source-4"
  end

  def test_reports_server_timing_coverage_percentiles_signals_and_worst_pages
    io = StringIO.new
    result = Crawlscope::Result.new(
      base_url: "https://example.com",
      sitemap_path: "/tmp/sitemap.xml",
      urls: [
        "https://example.com/fast",
        "https://example.com/slow",
        "https://example.com/malformed"
      ],
      pages: [
        page(
          "/fast",
          server_timing: 'total;dur=100, db;dur=20;desc="Primary", cache;desc="HIT"'
        ),
        page(
          "/slow",
          server_timing: 'total;dur=300, db;dur=80, cache;desc="MISS"'
        ),
        page("/malformed", server_timing: "bad metric;dur=10")
      ],
      issues: Crawlscope::IssueCollection.new
    )

    Crawlscope::Reporter.new(io: io).report(result)

    output = io.string
    assert_includes output, "Server Timing:"
    assert_includes output, "Coverage: 3/3 pages (100.0%); durations on 2 pages"
    assert_includes output, "Duration metrics (dur; milliseconds assumed):"
    assert_includes output, "total: 2 samples / 2 pages; avg 200ms; p50 200ms; p95 290ms; max 300ms"
    assert_includes output, 'db "Primary": 1 sample / 1 page'
    assert_includes output, 'cache "HIT": 1 sample / 1 page'
    assert_includes output, "Worst pages:"
    assert_includes output, "/slow: 300ms (total)"
    assert_includes output, "Ignored malformed entries: 1"
  end

  private

  def page(path = "/", server_timing: nil)
    url = "https://example.com#{path}"
    headers = {}
    headers["Server-Timing"] = server_timing unless server_timing.nil?

    Crawlscope::Page.new(
      url: url,
      normalized_url: url,
      final_url: url,
      normalized_final_url: url,
      status: 200,
      headers: headers,
      body: "",
      doc: nil
    )
  end
end
