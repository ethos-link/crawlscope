# frozen_string_literal: true

require "stringio"
require "test_helper"

class CrawlscopeStructuredDataReporterTest < Minitest::Test
  def test_reports_failures_and_report_path
    result = Crawlscope::StructuredData::Audit::Outcome.new(
      entries: [
        Crawlscope::StructuredData::Audit::Page.new(
          url: "https://example.com/article",
          status: 200,
          structured_items: [{source: "json-ld", data: {"@type" => "Article"}}],
          errors: [{type: "Article", source: "json-ld", errors: [{field: "headline", issue: "is required"}]}],
          fetch_error: nil,
          content_type: "text/html",
          skipped_reason: nil
        )
      ]
    )
    io = StringIO.new

    Crawlscope::StructuredData::Reporter.new(io: io, report_path: "/tmp/structured_data_report.json").report(result)

    output = io.string

    assert_includes output, "VALIDATION FAILED"
    assert_includes output, "VALIDATION ERRORS (1):"
    assert_includes output, "headline: is required"
    assert_includes output, "/tmp/structured_data_report.json"
  end

  def test_formats_real_schema_errors_in_summary_and_detailed_reports
    errors = Crawlscope::SchemaRegistry.default.validate({"@type" => "Article", "headline" => "x" * 111})
    result = Crawlscope::StructuredData::Audit::Outcome.new(entries: [
      Crawlscope::StructuredData::Audit::Page.new(
        url: "https://example.com/article", status: 200,
        structured_items: [{source: "json-ld", data: {"@type" => "Article"}}],
        errors: [{type: "Article", source: "json-ld", errors: errors}],
        fetch_error: nil, content_type: "text/html", skipped_reason: nil
      )
    ])
    io = StringIO.new
    reporter = Crawlscope::StructuredData::Reporter.new(io: io)

    reporter.report(result)
    assert_includes io.string, "JSON-LD:\n      - Article.headline: 111 characters; maximum 110"
    refute_includes io.string, "in schema"

    io.truncate(0)
    io.rewind
    reporter.details(result, debug: false, renderer: :http)
    assert_includes io.string, "Validation: FAILED\n  JSON-LD:\n    - Article.headline: 111 characters; maximum 110"
    refute_includes io.string, "=" * 80
    refute_includes io.string, "in schema"
    assert_includes errors.first[:issue], "in schema"
  end
end
