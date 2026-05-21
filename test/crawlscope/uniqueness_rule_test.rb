# frozen_string_literal: true

require "test_helper"

class CrawlscopeUniquenessRuleTest < Minitest::Test
  def test_reports_duplicate_title_description_and_content
    issues = Crawlscope::IssueCollection.new
    rule = Crawlscope::Rules::Uniqueness.new
    pages = [
      page(url: "https://example.com/a"),
      page(url: "https://example.com/b")
    ]

    rule.call(urls: pages.map(&:url), pages: pages, issues: issues, context: {})

    assert_equal %i[duplicate_content_fingerprint duplicate_meta_description duplicate_title].sort, issues.to_a.map(&:code).sort
  end

  def test_reports_near_duplicate_content
    issues = Crawlscope::IssueCollection.new
    rule = Crawlscope::Rules::Uniqueness.new
    pages = [
      page(url: "https://example.com/a", content: near_duplicate_content("reliable")),
      page(url: "https://example.com/b", content: near_duplicate_content("dependable"))
    ]

    rule.call(urls: pages.map(&:url), pages: pages, issues: issues, context: {})

    issue = issues.to_a.find { |item| item.code == :near_duplicate_content }
    assert issue
    assert_operator issue.details[:similarity], :>=, issue.details[:threshold]
  end

  def test_skips_near_duplicate_scan_when_page_count_exceeds_limit
    issues = Crawlscope::IssueCollection.new
    rule = Crawlscope::Rules::Uniqueness.new(max_near_duplicate_pages: 1)
    pages = [
      page(url: "https://example.com/a", content: near_duplicate_content("reliable")),
      page(url: "https://example.com/b", content: near_duplicate_content("dependable"))
    ]

    rule.call(urls: pages.map(&:url), pages: pages, issues: issues, context: {})

    skip_issue = issues.to_a.find { |item| item.code == :near_duplicate_scan_skipped }
    refute issues.to_a.any? { |item| item.code == :near_duplicate_content }
    assert_equal :warning, skip_issue.severity
    assert_equal({max_pages: 1, page_count: 2}, skip_issue.details)
  end

  private

  def near_duplicate_content(adjective)
    <<~TEXT.gsub(/\s+/, " ").strip
      This page summarizes practical hotel review patterns for operators who need #{adjective}
      service insights across locations. It compares recurring comments about staff, rooms,
      cleanliness, check-in, breakfast, parking, and amenities so teams can prioritize fixes.
      The analysis highlights repeat themes, explains why guests mention them, and keeps the
      wording focused on decisions that improve daily operations.
    TEXT
  end

  def page(url:, content: nil)
    repeated_text = content || ("Useful content " * 30).strip
    body = <<~HTML
      <html>
        <head>
          <title>Example Title</title>
          <meta name="description" content="Example description">
        </head>
        <body>
          <main>#{repeated_text}</main>
        </body>
      </html>
    HTML

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
