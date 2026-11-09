# frozen_string_literal: true

require "test_helper"

class CrawlscopeStructuredDataReportTest < Minitest::Test
  def test_outcome_and_report_agree_for_every_failure_kind_and_success_status
    cases = [
      {status: 200, structured_items: [], failure: :missing_data},
      {status: 201, structured_items: [], failure: :missing_data},
      {status: nil, structured_items: [], failure: :missing_data},
      {status: 200, fetch_error: "Fetch failed", failure: :http},
      {status: 404, fetch_error: "Not found", failure: :http},
      {status: 201, errors: [{errors: [{field: "name", issue: "is required"}]}], failure: :validation},
      {status: nil, errors: [{errors: [{field: "name", issue: "is required"}]}], failure: :validation},
      {status: 200, failure: nil},
      {status: 201, failure: nil},
      {status: nil, failure: nil},
      {status: 200, structured_items: [], skipped_reason: "non-html", failure: nil}
    ]
    cases.each do |attributes|
      attributes = attributes.dup
      failure = attributes.delete(:failure)
      defaults = {url: "https://example.com/page", status: 200, structured_items: [{source: "json-ld", data: {"@type" => "WebPage"}}],
                  errors: [], fetch_error: nil, content_type: "text/html", skipped_reason: nil}
      entry = Crawlscope::StructuredData::Audit::Page.new(**defaults.merge(attributes))
      outcome = Crawlscope::StructuredData::Audit::Outcome.new(entries: [entry])
      report = Crawlscope::StructuredData::Report.new(outcome)

      assert_equal failure.nil?, outcome.ok?, attributes.inspect
      assert_equal outcome.ok?, report.all_valid?, attributes.inspect
      assert_equal failure ? 1 : 0, report.failure_count, attributes.inspect
      assert_equal (failure == :http) ? [entry] : [], report.http_errors
      assert_equal (failure == :missing_data) ? [entry] : [], report.missing_data
      assert_equal (failure == :validation) ? [entry] : [], report.validation_errors
    end
  end

  def test_results_maps_validation_errors_and_skips
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
        ),
        Crawlscope::StructuredData::Audit::Page.new(
          url: "https://example.com/feed.xml",
          status: 200,
          structured_items: [],
          errors: [],
          fetch_error: nil,
          content_type: "application/xml",
          skipped_reason: "non-html"
        )
      ]
    )

    report = Crawlscope::StructuredData::Report.new(result)

    assert_equal [{field: "headline", issue: "is required"}], report.results["https://example.com/article"][:validation_errors]
    assert_equal "non-html", report.results["https://example.com/feed.xml"][:skipped_reason]
    assert_empty report.missing_data
    assert_equal 1, report.validation_errors.size
  end
end
