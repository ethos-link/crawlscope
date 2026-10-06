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

    assert_equal %i[duplicate_content_fingerprint duplicate_meta_description duplicate_pages_without_canonical duplicate_title].sort, issues.to_a.map(&:code).sort
  end

  def test_allows_duplicate_pages_when_canonicals_are_present
    issues = Crawlscope::IssueCollection.new
    rule = Crawlscope::Rules::Uniqueness.new
    pages = [
      page(url: "https://example.com/a", canonical: "https://example.com/a"),
      page(url: "https://example.com/b", canonical: "https://example.com/a")
    ]

    rule.call(urls: pages.map(&:url), pages: pages, issues: issues, context: {})

    refute_includes issues.to_a.map(&:code), :duplicate_pages_without_canonical
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

  def test_does_not_report_redirect_aliases_as_duplicate_pages
    pages = [
      page(url: "https://example.com/old", final_url: "https://example.com/current"),
      page(url: "https://example.com/alias", final_url: "https://example.com/current"),
      page(url: "https://example.com/current")
    ]
    issues = Crawlscope::IssueCollection.new

    Crawlscope::Rules::Uniqueness.new.call(urls: pages.map(&:url), pages: pages, issues: issues, context: {})

    assert_empty issues.to_a
  end

  def test_reports_direct_duplicate_pages_without_including_redirect_aliases
    pages = [
      page(url: "https://example.com/old", final_url: "https://example.com/a"),
      page(url: "https://example.com/a"),
      page(url: "https://example.com/b")
    ]
    issues = Crawlscope::IssueCollection.new

    Crawlscope::Rules::Uniqueness.new.call(urls: pages.map(&:url), pages: pages, issues: issues, context: {})

    assert_equal 4, issues.size
    issues.each do |issue|
      assert_equal ["https://example.com/a", "https://example.com/b"], issue.details[:urls]
    end
  end

  def test_excludes_redirects_from_near_duplicate_checks_and_scan_limit
    pages = [
      page(url: "https://example.com/old", final_url: "https://example.com/other", content: near_duplicate_content("reliable")),
      page(url: "https://example.com/current", content: near_duplicate_content("dependable"))
    ]

    [Crawlscope::Rules::Uniqueness.new, Crawlscope::Rules::Uniqueness.new(max_near_duplicate_pages: 1)].each do |rule|
      issues = Crawlscope::IssueCollection.new
      rule.call(urls: pages.map(&:url), pages: pages, issues: issues, context: {})

      assert_empty issues.to_a
    end
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

  def page(url:, content: nil, canonical: nil, final_url: url)
    repeated_text = content || ("Useful content " * 30).strip
    canonical_tag = canonical ? %(<link rel="canonical" href="#{canonical}">) : ""
    body = <<~HTML
      <html>
        <head>
          <title>Example Title</title>
          <meta name="description" content="Example description">
          #{canonical_tag}
        </head>
        <body>
          <main>#{repeated_text}</main>
        </body>
      </html>
    HTML

    Crawlscope::Page.new(
      url: url,
      normalized_url: url,
      final_url: final_url,
      normalized_final_url: final_url,
      status: 200,
      headers: {"content-type" => "text/html"},
      body: body,
      doc: Nokogiri::HTML(body)
    )
  end
end
