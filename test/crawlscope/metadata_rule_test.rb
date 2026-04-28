# frozen_string_literal: true

require "test_helper"

class CrawlscopeMetadataRuleTest < Minitest::Test
  def test_reports_short_meta_description_multiple_h1_and_incomplete_open_graph
    issues = Crawlscope::IssueCollection.new

    Crawlscope::Rules::Metadata.new.call(
      urls: [page.url],
      pages: [page],
      issues: issues
    )

    codes = issues.to_a.map(&:code)
    assert_includes codes, :meta_description_too_short
    assert_includes codes, :multiple_h1
    assert_includes codes, :incomplete_open_graph_tags
  end

  def test_allows_localhost_page_with_matching_production_canonical_path
    issues = Crawlscope::IssueCollection.new
    local_page = page(
      url: "http://localhost:3000/about",
      body: <<~HTML
        <html>
          <head>
            <title>About</title>
            <meta name="description" content="A clear description that is long enough for search snippets, local validation checks, and realistic production metadata audits.">
            <link rel="canonical" href="https://www.example.com/about">
            <meta property="og:title" content="About">
            <meta property="og:description" content="About page">
            <meta property="og:url" content="https://www.example.com/about">
            <meta property="og:type" content="website">
            <meta property="og:image" content="https://www.example.com/icon.png">
          </head>
          <body><main><h1>About</h1></main></body>
        </html>
      HTML
    )

    Crawlscope::Rules::Metadata.new.call(
      urls: [local_page.url],
      pages: [local_page],
      issues: issues
    )

    refute_includes issues.to_a.map(&:code), :canonical_mismatch
  end

  private

  def page(url: "https://example.com/about", body: nil)
    body ||= <<~HTML
      <html>
        <head>
          <title>About</title>
          <meta name="description" content="Too short">
          <link rel="canonical" href="https://example.com/about">
          <meta property="og:title" content="About">
        </head>
        <body><main><h1>About</h1><h1>Team</h1></main></body>
      </html>
    HTML

    Crawlscope::Page.new(
      url: url,
      normalized_url: Crawlscope::Url.normalize(url, base_url: url),
      final_url: url,
      normalized_final_url: Crawlscope::Url.normalize(url, base_url: url),
      status: 200,
      headers: {"content-type" => "text/html"},
      body: body,
      doc: Nokogiri::HTML(body)
    )
  end
end
