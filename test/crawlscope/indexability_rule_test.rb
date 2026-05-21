# frozen_string_literal: true

require "test_helper"

class CrawlscopeIndexabilityRuleTest < Minitest::Test
  def test_reports_meta_noindex
    issues = Crawlscope::IssueCollection.new
    page = page_with(
      body: <<~HTML
        <html>
          <head><meta name="robots" content="noindex, follow"></head>
          <body><main>Visible content</main></body>
        </html>
      HTML
    )

    Crawlscope::Rules::Indexability.new.call(urls: [page.url], pages: [page], issues: issues)

    issue = issues.to_a.fetch(0)
    assert_equal :noindex_meta, issue.code
    assert_equal :error, issue.severity
    assert_equal "noindex, follow", issue.details[:content]
  end

  def test_reports_x_robots_tag_noindex
    issues = Crawlscope::IssueCollection.new
    page = page_with(headers: {"X-Robots-Tag" => "noindex"})

    Crawlscope::Rules::Indexability.new.call(urls: [page.url], pages: [page], issues: issues)

    issue = issues.to_a.fetch(0)
    assert_equal :noindex_header, issue.code
    assert_equal :error, issue.severity
    assert_equal "noindex", issue.details[:content]
  end

  def test_reports_x_robots_tag_noindex_for_non_html_response
    issues = Crawlscope::IssueCollection.new
    page = page_with(
      body: "%PDF-1.7",
      doc: nil,
      headers: {"content-type" => "application/pdf", "X-Robots-Tag" => "noindex"}
    )

    Crawlscope::Rules::Indexability.new.call(urls: [page.url], pages: [page], issues: issues)

    issue = issues.to_a.fetch(0)
    assert_equal :noindex_header, issue.code
    assert_equal :error, issue.severity
    assert_equal "noindex", issue.details[:content]
  end

  def test_reports_scoped_x_robots_tag_noindex
    issues = Crawlscope::IssueCollection.new
    page = page_with(headers: {"X-Robots-Tag" => "googlebot: noindex, nofollow"})

    Crawlscope::Rules::Indexability.new.call(urls: [page.url], pages: [page], issues: issues)

    issue = issues.to_a.fetch(0)
    assert_equal :noindex_header, issue.code
    assert_equal "googlebot: noindex, nofollow", issue.details[:content]
  end

  def test_reports_x_robots_tag_none
    issues = Crawlscope::IssueCollection.new
    page = page_with(headers: {"X-Robots-Tag" => "none"})

    Crawlscope::Rules::Indexability.new.call(urls: [page.url], pages: [page], issues: issues)

    issue = issues.to_a.fetch(0)
    assert_equal :noindex_header, issue.code
    assert_equal "none", issue.details[:content]
  end

  private

  def page_with(body: nil, doc: :parse, headers: {"content-type" => "text/html"})
    body ||= <<~HTML
      <html>
        <head><title>Indexable</title></head>
        <body><main>Visible content</main></body>
      </html>
    HTML

    Crawlscope::Page.new(
      url: "https://example.com/page",
      normalized_url: "https://example.com/page",
      final_url: "https://example.com/page",
      normalized_final_url: "https://example.com/page",
      status: 200,
      headers: headers,
      body: body,
      doc: (doc == :parse) ? Nokogiri::HTML(body) : doc
    )
  end
end
