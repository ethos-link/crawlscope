# frozen_string_literal: true

require "test_helper"

class CrawlscopeServerTimingSummaryTest < Minitest::Test
  def test_aggregates_coverage_percentiles_signals_and_worst_pages
    pages = [
      page("/fast", 'total;dur=100, db;dur=20, cache;desc="HIT"'),
      page("/typical", 'total;dur=200, db;dur=50, cache;desc="MISS"'),
      page("/slow", 'total;dur=300, db;dur=80, cache;desc="HIT", miss'),
      page("/no-header"),
      page("/malformed", "bad metric;dur=10")
    ]

    summary = Crawlscope::ServerTiming::Summary.new(pages)

    assert summary.present?
    assert_equal 5, summary.pages.size
    assert_equal 4, summary.coverage
    assert_equal 3, summary.duration_pages
    assert_equal 1, summary.invalid_count

    total = summary.metrics.find { |metric| metric[:name] == "total" }
    assert_equal 3, total[:samples]
    assert_equal 3, total[:pages]
    assert_in_delta 200.0, total[:average]
    assert_in_delta 200.0, total[:p50]
    assert_in_delta 290.0, total[:p95]
    assert_in_delta 300.0, total[:maximum]

    hit = summary.signals.find do |signal|
      signal[:name] == "cache" && signal[:description] == "HIT"
    end
    assert_equal 2, hit[:samples]
    assert_equal 2, hit[:pages]

    assert_equal(
      [
        ["https://example.com/slow", "total", 300.0],
        ["https://example.com/typical", "total", 200.0]
      ],
      summary.worst_pages(limit: 2).map do |sample|
        [sample[:page].url, sample[:metric].name, sample[:metric].duration]
      end
    )
  end

  def test_is_absent_when_no_pages_publish_the_header
    summary = Crawlscope::ServerTiming::Summary.new([page("/one"), page("/two")])

    refute summary.present?
    assert_empty summary.metrics
    assert_empty summary.signals
    assert_empty summary.worst_pages
  end

  def test_returns_ten_worst_pages_by_default
    pages = 12.times.map do |index|
      page("/page-#{index + 1}", "total;dur=#{index + 1}")
    end

    summary = Crawlscope::ServerTiming::Summary.new(pages)

    assert_equal 10, summary.worst_pages.size
    assert_equal "https://example.com/page-12", summary.worst_pages.first[:page].url
    assert_equal "https://example.com/page-3", summary.worst_pages.last[:page].url
  end

  private

  def page(path, server_timing = nil)
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
