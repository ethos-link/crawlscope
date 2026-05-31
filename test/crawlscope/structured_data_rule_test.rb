# frozen_string_literal: true

require "test_helper"

class CrawlscopeStructuredDataRuleTest < Minitest::Test
  def test_reports_schema_errors_for_invalid_article_markup
    issues = Crawlscope::IssueCollection.new
    rule = Crawlscope::Rules::StructuredData.new
    page = page(
      url: "https://example.com/articles/test",
      body: <<~HTML
        <html>
          <head>
            <script type="application/ld+json">
              {"@context":"https://schema.org","@type":"Article"}
            </script>
          </head>
          <body>
            <main><h1>Article</h1></main>
          </body>
        </html>
      HTML
    )

    rule.call(
      urls: [page.url],
      pages: [page],
      issues: issues,
      context: {schema_registry: Crawlscope::SchemaRegistry.default}
    )

    assert_equal [:structured_data_schema_error], issues.to_a.map(&:code)
    assert_includes issues.to_a.first.message, "headline"
  end

  def test_reports_parse_errors_for_invalid_json_ld
    issues = Crawlscope::IssueCollection.new
    rule = Crawlscope::Rules::StructuredData.new
    page = page(
      url: "https://example.com/articles/test",
      body: <<~HTML
        <html>
          <head>
            <script type="application/ld+json">
              {"@context":"https://schema.org","@type":"Article"
            </script>
          </head>
        </html>
      HTML
    )

    rule.call(
      urls: [page.url],
      pages: [page],
      issues: issues,
      context: {schema_registry: Crawlscope::SchemaRegistry.default}
    )

    assert_equal [:structured_data_parse_error], issues.to_a.map(&:code)
  end

  def test_reports_missing_structured_data_for_html_pages
    issues = Crawlscope::IssueCollection.new
    rule = Crawlscope::Rules::StructuredData.new
    page = page(
      url: "https://example.com/articles/test",
      body: "<html><body><main><h1>Article</h1></main></body></html>"
    )

    rule.call(
      urls: [page.url],
      pages: [page],
      issues: issues,
      context: {schema_registry: Crawlscope::SchemaRegistry.default}
    )

    assert_equal [:missing_structured_data], issues.to_a.map(&:code)
    assert_equal "no structured data found; add JSON-LD or microdata markup", issues.to_a.first.message
    assert_equal ["json-ld", "microdata"], issues.to_a.first.details[:expected_sources]
  end

  def test_reports_structured_data_missing_type
    issues = Crawlscope::IssueCollection.new
    rule = Crawlscope::Rules::StructuredData.new
    page = page(
      url: "https://example.com/articles/test",
      body: <<~HTML
        <html>
          <head>
            <script type="application/ld+json">
              {"@context":"https://schema.org","headline":"Untyped article"}
            </script>
          </head>
          <body><h1>Article</h1></body>
        </html>
      HTML
    )

    rule.call(
      urls: [page.url],
      pages: [page],
      issues: issues,
      context: {schema_registry: Crawlscope::SchemaRegistry.default}
    )

    assert_includes issues.to_a.map(&:code), :structured_data_missing_type
  end

  def test_reports_graph_entries_missing_type
    issues = Crawlscope::IssueCollection.new
    rule = Crawlscope::Rules::StructuredData.new
    page = page(
      url: "https://example.com/articles/test",
      body: <<~HTML
        <html>
          <head>
            <script type="application/ld+json">
              {"@context":"https://schema.org","@type":"WebPage","@graph":[{"name":"Untyped node"}]}
            </script>
          </head>
          <body><h1>Article</h1></body>
        </html>
      HTML
    )

    rule.call(
      urls: [page.url],
      pages: [page],
      issues: issues,
      context: {schema_registry: Crawlscope::SchemaRegistry.default}
    )

    issue = issues.to_a.find { |item| item.code == :structured_data_missing_type }
    assert issue
    assert_equal ["$.@graph[0]"], issue.details[:paths]
  end

  def test_validates_job_posting_markup
    issues = Crawlscope::IssueCollection.new
    rule = Crawlscope::Rules::StructuredData.new
    page = page(
      url: "https://example.com/careers/sales-partner",
      body: <<~HTML
        <html>
          <head>
            <script type="application/ld+json">
              {
                "@context":"https://schema.org/",
                "@type":"JobPosting",
                "title":"Sales Partner",
                "description":"A real role description.",
                "datePosted":"2026-04-28",
                "hiringOrganization":{"@type":"Organization","name":"Example","sameAs":"https://example.com/","logo":"https://example.com/icon.png"},
                "jobLocationType":"TELECOMMUTE",
                "applicantLocationRequirements":[{"@type":"Country","name":"South Africa"}]
              }
            </script>
          </head>
          <body><h1>Sales Partner</h1></body>
        </html>
      HTML
    )

    rule.call(
      urls: [page.url],
      pages: [page],
      issues: issues,
      context: {schema_registry: Crawlscope::SchemaRegistry.default}
    )

    assert_empty issues.to_a
  end

  def test_reports_schema_errors_for_invalid_job_posting_markup
    issues = Crawlscope::IssueCollection.new
    rule = Crawlscope::Rules::StructuredData.new
    page = page(
      url: "https://example.com/careers/sales-partner",
      body: <<~HTML
        <html>
          <head>
            <script type="application/ld+json">
              {"@context":"https://schema.org","@type":"JobPosting","title":"Sales Partner"}
            </script>
          </head>
          <body><h1>Sales Partner</h1></body>
        </html>
      HTML
    )

    rule.call(
      urls: [page.url],
      pages: [page],
      issues: issues,
      context: {schema_registry: Crawlscope::SchemaRegistry.default}
    )

    assert_equal [:structured_data_schema_error], issues.to_a.map(&:code)
    assert_includes issues.to_a.first.message, "description"
  end

  def test_reports_missing_job_posting_for_career_detail_pages
    issues = Crawlscope::IssueCollection.new
    rule = Crawlscope::Rules::StructuredData.new
    page = page(
      url: "https://example.com/careers/sales-partner",
      body: <<~HTML
        <html>
          <head>
            <script type="application/ld+json">
              {"@context":"https://schema.org","@type":"WebPage","name":"Sales Partner"}
            </script>
          </head>
          <body><h1>Sales Partner</h1></body>
        </html>
      HTML
    )

    rule.call(
      urls: [page.url],
      pages: [page],
      issues: issues,
      context: {schema_registry: Crawlscope::SchemaRegistry.default}
    )

    assert_equal [:missing_job_posting], issues.to_a.map(&:code)
  end

  private

  def page(url:, body:)
    doc = Nokogiri::HTML(body)

    Crawlscope::Page.new(
      url: url,
      normalized_url: url,
      final_url: url,
      normalized_final_url: url,
      status: 200,
      headers: {"content-type" => "text/html"},
      body: body,
      doc: doc
    )
  end
end
