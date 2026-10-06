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
    refute_includes output, "Summary:"
    assert_includes output, "Links: Too few incoming links without nofollow (4 warnings)"
    assert_includes output, "  - /page-1  incoming links without nofollow: 1; minimum 2\n      linked from: /source-1"
    assert_includes output, "  - /page-4  incoming links without nofollow: 1; minimum 2\n      linked from: /source-4"
    assert_includes output, "Metadata: Missing title (1 warning)"
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

  def test_reports_every_issue_in_large_groups
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

    assert_includes output, "Links: Too few incoming links without nofollow (21 warnings)"
    assert_includes output, "  - /page-20  incoming links without nofollow: 1; minimum 2"
    assert_includes output, "  - /page-21"
    refute_includes output, "  ... 1 more"
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

    assert_includes io.string, "unique words: 24.9%; minimum 25%"
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

    assert_includes output, "Sitemaps: Linked pages missing from sitemap (4 warnings)"
    assert_includes output, "  - /overview-1  linked page is missing from sitemap\n      linked from: /source-1"
    assert_includes output, "  - /overview-4  linked page is missing from sitemap\n      linked from: /source-4"
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
    assert_includes output, "Response times (ms):"
    assert_includes output, "total: 2 samples / 2 pages; avg 200ms; p50 200ms; p95 290ms; max 300ms"
    assert_includes output, 'db "Primary": 1 sample / 1 page'
    assert_includes output, 'cache "HIT": 1 sample / 1 page'
    assert_includes output, "Pages above 50 ms:"
    assert_includes output, "/slow: 300ms (total)"
    assert_includes output, "Ignored malformed entries: 1"
  end

  def test_reports_redirect_destination_once_and_keeps_external_origins
    [:sitemap_redirect_url, :redirected_page, :internal_link_redirects].each do |code|
      output = report_issues({code: code, details: {final_url: "https://example.com/new?lang=en#top", status: 200}})

      assert_includes output, "redirects to /new?lang=en#top"
      assert_equal 1, output.scan("/new?lang=en#top").size
      refute_includes output, "status 200"
      refute_includes output, "final:"
    end

    ["https://other.example/new", "http://example.com/new", "https://example.com:8443/new"].each do |destination|
      output = report_issues({code: :sitemap_redirect_url, details: {final_url: destination, status: 200}})
      assert_includes output, "redirects to #{destination}"
    end
  end

  def test_reports_canonical_target_and_explains_sitemap_mismatch
    ["https://example.com/preferred?lang=en", "/preferred?lang=en"].each do |canonical|
      output = report_issues({code: :non_canonical_page_in_sitemap, category: :sitemaps, details: {canonical: canonical}})
      assert_includes output, "/page  sitemap lists this URL, but its canonical points to /preferred?lang=en"
    end

    output = report_issues({code: :canonical_mismatch, details: {canonical: "https://other.example/page"}})
    assert_includes output, "canonical points to a different URL: https://other.example/page"
  end

  def test_reports_real_schema_errors_on_separate_lines_without_raw_json
    errors = Crawlscope::SchemaRegistry.default.validate({"@type" => "Article", "headline" => "x" * 111, "author" => "Name"})
    output = report_issues({code: :structured_data_schema_error, category: :structured_data, details: {source: "json-ld", errors: errors}})

    assert_includes output, "Structured data: Schema errors (1 warning)"
    assert_includes output, "  - /page  JSON-LD\n      Article.headline: 111 characters; maximum 110\n      Article.author: must be object (got string)"
    refute_includes output, "in schema"
    refute_includes output, '"field":'
    assert_includes errors.first[:issue], "in schema"
  end

  def test_reports_link_failures_without_repeating_status_or_sources
    output = report_issues(
      {code: :broken_internal_link, message: "broken internal link (HTTP 404, sources: https://example.com/source)", details: {status: 404, source_urls: ["https://example.com/source"]}},
      {code: :unresolved_internal_link, details: {error: "timeout", source_urls: ["https://example.com/source"]}},
      {code: :internal_link_redirects, details: {final_url: "https://example.com/new", source_urls: ["https://example.com/source"], status: 200}}
    )

    assert_includes output, "linked URL returns HTTP 404\n      linked from: /source"
    assert_equal 1, output.scan("404").size
    assert_includes output, "cannot check linked URL: timeout\n      linked from: /source"
    assert_includes output, "redirects to /new (final HTTP 200)\n      linked from: /source"
    refute_includes output, "https://example.com/source"
  end

  def test_reports_canonical_status_with_both_relevant_urls
    output = report_issues(
      {code: :canonical_points_to_redirect, details: {canonical: "https://example.com/old", final_url: "https://example.com/new", status: 200}},
      {code: :canonical_points_to_error, details: {canonical: "https://example.com/missing", status: 404}},
      {code: :canonical_no_internal_inlinks, message: "canonical URL has no incoming internal links without nofollow", details: {source_url: "https://example.com/article"}}
    )

    assert_includes output, "canonical /old redirects to /new"
    assert_includes output, "canonical /missing returns HTTP 404"
    assert_includes output, "      canonical on: /article"
    refute_includes output, "linked from: /article"
  end

  def test_reports_errors_before_larger_warning_groups
    warnings = 3.times.map { |index| {code: :missing_title, category: :metadata, url: "https://example.com/#{index}"} }
    output = report_issues(*warnings, {code: :fetch_failed, category: :crawl, severity: :error, message: "timeout"})

    assert_operator output.index("Crawl: Fetch failed"), :<, output.index("Metadata: Missing title")
    refute_includes output, "metadata / missing_title"
  end

  def test_reports_full_duplicate_values_and_every_url
    urls = 5.times.map { |index| "https://example.com/page-#{index}" }
    value = "A long description " * 20
    details = {value: value, urls: urls}
    output = report_issues({code: :duplicate_meta_description, category: :uniqueness, details: details})

    assert_includes output, "same meta description:"
    assert_includes output, value
    urls.each { |url| assert_includes output, "      page: #{URI(url).path}" }
    refute_includes output, "more)"
    assert_equal value, details[:value]
    assert_equal 5, details[:urls].size
  end

  def test_reports_measurements_with_units_and_limits
    output = report_issues(
      {code: :low_visible_text_ratio, details: {ratio: 0.079, threshold: 0.08}},
      {code: :thin_visible_text, details: {word_count: 40, minimum: 250}},
      {code: :near_duplicate_content, details: {similarity: 0.925, threshold: 0.9, urls: ["https://example.com/a", "https://example.com/b"]}},
      {code: :near_duplicate_scan_skipped, details: {page_count: 300, max_pages: 250}}
    )

    assert_includes output, "visible text / HTML bytes: 7.9%; minimum 8%"
    assert_includes output, "visible words: 40; minimum 250"
    assert_includes output, "text similarity: 92.5%; threshold 90%\n      page: /a\n      page: /b"
    assert_includes output, "similar-page check skipped: 300 pages; limit 250"
  end

  def test_reports_all_source_and_target_urls_on_labeled_lines
    sources = 6.times.map { |index| "https://example.com/source-#{index}" }
    targets = 6.times.map { |index| "https://example.com/target-#{index}" }
    output = report_issues({code: :nofollow_internal_outlinks, details: {source_url: sources.first, source_urls: sources, target_urls: targets}})

    sources.each { |url| assert_includes output, "      linked from: #{URI(url).path}\n" }
    targets.each { |url| assert_includes output, "      links to: #{URI(url).path}\n" }
    assert_equal 1, output.scan("linked from: /source-0").size
    refute_includes output, "more"
  end

  def test_reports_all_timed_pages_and_full_descriptions
    description = "A detailed metric description " * 5
    pages = 12.times.map { |index| page("/timed-#{index}", server_timing: %(total;dur=#{index + 60};desc="#{description}")) }
    result = Crawlscope::Result.new(base_url: "https://example.com", sitemap_path: "/sitemap.xml", urls: pages.map(&:url), pages: pages, issues: Crawlscope::IssueCollection.new)
    io = StringIO.new
    Crawlscope::Reporter.new(io: io).report(result)

    pages.each { |item| assert_includes io.string, "#{URI(item.url).path}:" }
    assert_includes io.string, description
  end

  def test_length_rows_do_not_repeat_the_field_or_limit_from_the_heading
    output = report_issues(
      {code: :meta_description_too_long, category: :metadata, message: "meta description: 184 characters; maximum 160", details: {length: 184}},
      {code: :meta_description_too_short, category: :metadata, details: {length: 40, minimum: 110}},
      {code: :title_too_long, category: :metadata, details: {length: 80}}
    )

    assert_includes output, "Metadata: Meta description exceeds 160 characters (1 warning)\n  - /page  184 characters"
    assert_includes output, "Metadata: Meta description below 110 characters (1 warning)\n  - /page  40 characters"
    assert_includes output, "Metadata: Title exceeds 72 characters (1 warning)\n  - /page  80 characters"
    refute_includes output, "meta description:"
    refute_includes output, "maximum 160"
  end

  def test_lists_only_pages_strictly_above_50_milliseconds
    pages = [page("/fast", server_timing: "total;dur=49"), page("/boundary", server_timing: "total;dur=50"), page("/slow", server_timing: "total;dur=50.001")]
    result = Crawlscope::Result.new(base_url: "https://example.com", sitemap_path: "/sitemap.xml", urls: pages.map(&:url), pages: pages, issues: Crawlscope::IssueCollection.new)
    io = StringIO.new
    Crawlscope::Reporter.new(io: io).report(result)

    assert_includes io.string, "Pages above 50 ms:\n    /slow: 50.001ms (total)"
    refute_includes io.string, "/fast:"
    refute_includes io.string, "/boundary:"
    assert_includes io.string, "Coverage: 3/3 pages"
    assert_includes io.string, "total: 3 samples / 3 pages"
  end

  def test_omits_slow_page_section_when_all_pages_are_at_or_below_50_milliseconds
    pages = [page("/boundary", server_timing: "total;dur=50")]
    result = Crawlscope::Result.new(base_url: "https://example.com", sitemap_path: "/sitemap.xml", urls: pages.map(&:url), pages: pages, issues: Crawlscope::IssueCollection.new)
    io = StringIO.new
    Crawlscope::Reporter.new(io: io).report(result)

    refute_includes io.string, "Pages above"
    assert_includes io.string, "Server Timing:"
  end

  private

  def report_issues(*attributes, base_url: "https://example.com")
    issues = Crawlscope::IssueCollection.new
    attributes.each do |values|
      defaults = {severity: :warning, category: :links, url: "#{base_url}/page", message: "original message", details: {}}
      issues.add(**defaults.merge(values))
    end
    result = Crawlscope::Result.new(base_url: base_url, sitemap_path: "/sitemap.xml", urls: [], pages: [], issues: issues)
    io = StringIO.new
    Crawlscope::Reporter.new(io: io).report(result)
    io.string
  end

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
