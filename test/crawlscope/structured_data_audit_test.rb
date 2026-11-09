# frozen_string_literal: true

require "test_helper"

class CrawlscopeStructuredDataAuditTest < Minitest::Test
  def test_sitemap_and_direct_audits_agree_on_structured_data_validity
    cases = [
      ["<h1>No markup</h1>", :missing_structured_data],
      ['<script type="application/ld+json">{</script>', :structured_data_parse_error],
      ['<script type="application/ld+json">{"name":"Untyped"}</script>', :structured_data_missing_type],
      ['<script type="application/ld+json">{"@type":"WebPage","@graph":[{"name":"Untyped"}]}</script>', :structured_data_missing_type],
      ['<script type="application/ld+json">{"@type":"Article"}</script>', :structured_data_schema_error],
      ['<script type="application/ld+json">{"@type":"WebPage","name":"Example"}</script>', nil],
      ['<div itemscope itemtype="https://schema.org/WebPage"><span itemprop="name">Example</span></div>', nil]
    ]
    registry = Crawlscope::SchemaRegistry.default
    cases.each do |body, expected_code|
      page = html_page(url: "https://example.com/page", body: body)
      browser = FakeBrowser.new(page: page)
      outcome = Crawlscope::StructuredData::Audit.new(browser_factory: -> { browser }, renderer: :browser,
        schema_registry: registry, timeout_seconds: 20).call(urls: [page.url])
      issues = Crawlscope::IssueCollection.new
      Crawlscope::Rules::StructuredData.new.call(urls: [page.url], pages: [page], issues: issues, context: {schema_registry: registry})

      assert_equal expected_code.nil?, outcome.ok?, body
      assert_equal expected_code ? [expected_code] : [], issues.map(&:code), body
      assert_equal outcome.ok?, Crawlscope::StructuredData::Report.new(outcome).all_valid?
      schema_issue = issues.find { |issue| issue.code == :structured_data_schema_error }
      assert_equal schema_issue.details[:errors], outcome.entries.first.errors.first[:errors] if schema_issue
      assert browser.closed
    end
  end

  class FakeBrowser
    attr_reader :closed

    def initialize(page:)
      @page = page
      @closed = false
    end

    def close
      @closed = true
    end

    def fetch(_url)
      @page
    end
  end

  def test_reports_schema_errors_for_invalid_article_markup
    page = html_page(
      url: "https://example.com/articles/test",
      body: <<~HTML
        <html>
          <head>
            <script type="application/ld+json">
              {"@context":"https://schema.org","@type":"Article"}
            </script>
          </head>
        </html>
      HTML
    )
    browser = FakeBrowser.new(page: page)
    audit = Crawlscope::StructuredData::Audit.new(
      browser_factory: -> { browser },
      renderer: :browser,
      schema_registry: Crawlscope::SchemaRegistry.default,
      timeout_seconds: 20
    )

    result = audit.call(urls: [page.url])

    refute result.ok?
    assert_equal 1, result.entries.size
    assert_equal "Article", result.entries.first.errors.first[:type]
    assert browser.closed
  end

  def test_reports_fetch_errors_for_non_success_statuses
    page = Crawlscope::Page.new(
      url: "https://example.com/missing",
      normalized_url: "https://example.com/missing",
      final_url: "https://example.com/missing",
      normalized_final_url: "https://example.com/missing",
      status: 404,
      headers: {"content-type" => "text/html"},
      body: "",
      doc: Nokogiri::HTML("")
    )
    browser = FakeBrowser.new(page: page)
    audit = Crawlscope::StructuredData::Audit.new(
      browser_factory: -> { browser },
      renderer: :browser,
      schema_registry: Crawlscope::SchemaRegistry.default,
      timeout_seconds: 20
    )

    result = audit.call(urls: [page.url])

    refute result.ok?
    assert_equal "Non-success status", result.entries.first.fetch_error
  end

  def test_skips_non_html_responses_without_treating_them_as_missing_data
    page = Crawlscope::Page.new(
      url: "https://example.com/feed.xml",
      normalized_url: "https://example.com/feed.xml",
      final_url: "https://example.com/feed.xml",
      normalized_final_url: "https://example.com/feed.xml",
      status: 200,
      headers: {"content-type" => "application/xml"},
      body: "<feed></feed>",
      doc: nil
    )
    browser = FakeBrowser.new(page: page)
    audit = Crawlscope::StructuredData::Audit.new(
      browser_factory: -> { browser },
      renderer: :browser,
      schema_registry: Crawlscope::SchemaRegistry.default,
      timeout_seconds: 20
    )

    result = audit.call(urls: [page.url])

    assert result.ok?
    assert_equal "application/xml", result.entries.first.content_type
    assert_equal "non-html", result.entries.first.skipped_reason
    assert_predicate result.entries.first, :structured_data_found?
  end

  private

  def html_page(url:, body:)
    Crawlscope::Page.new(
      url: url,
      normalized_url: url,
      final_url: url,
      normalized_final_url: url,
      status: 200,
      headers: {"content-type" => "text/html"},
      body: body,
      doc: Nokogiri::HTML(body)
    )
  end
end
