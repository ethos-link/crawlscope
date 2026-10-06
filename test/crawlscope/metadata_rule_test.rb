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

  def test_reports_multiple_title_multiple_descriptions_empty_h1_and_sitemap_canonical_mismatch
    issues = Crawlscope::IssueCollection.new
    invalid_page = page(
      body: <<~HTML
        <html>
          <head>
            <title>About</title>
            <title>Duplicate About</title>
            <meta name="description" content="A clear description that is long enough for search snippets, local validation checks, and realistic production metadata audits.">
            <meta name="description" content="Duplicate description">
            <link rel="canonical" href="https://example.com/canonical-about">
            <meta property="og:title" content="About">
            <meta property="og:description" content="About page">
            <meta property="og:url" content="https://example.com/about">
            <meta property="og:type" content="website">
            <meta property="og:image" content="https://example.com/icon.png">
          </head>
          <body><main><h1> </h1></main></body>
        </html>
      HTML
    )

    Crawlscope::Rules::Metadata.new.call(
      urls: [invalid_page.url],
      pages: [invalid_page],
      issues: issues
    )

    codes = issues.to_a.map(&:code)
    assert_includes codes, :multiple_title_tags
    assert_includes codes, :multiple_meta_descriptions
    assert_includes codes, :empty_h1
    refute_includes codes, :canonical_mismatch
    assert_includes codes, :non_canonical_page_in_sitemap
    mismatch = issues.find { |issue| issue.code == :non_canonical_page_in_sitemap }
    assert_equal "sitemap lists this URL, but its canonical points to https://example.com/canonical-about", mismatch.message
    assert_equal "https://example.com/canonical-about", mismatch.details[:canonical]
  end

  def test_length_messages_include_measurement_units_and_limit
    issues = Crawlscope::IssueCollection.new
    long_page = page(body: %(<html><head><title>#{"T" * 73}</title><meta name="description" content="#{"D" * 161}"></head></html>))

    Crawlscope::Rules::Metadata.new.call(urls: [long_page.url], pages: [long_page], issues: issues)

    assert_equal "title: 73 characters; maximum 72", issues.find { |issue| issue.code == :title_too_long }.message
    assert_equal "meta description: 161 characters; maximum 160", issues.find { |issue| issue.code == :meta_description_too_long }.message
  end

  def test_does_not_apply_destination_metadata_to_redirect_alias
    redirected = page(url: "https://example.com/old", final_url: "https://example.com/new", body: '<html><head><link rel="canonical" href="https://example.com/new"></head></html>')
    issues = Crawlscope::IssueCollection.new

    Crawlscope::Rules::Metadata.new.call(urls: [redirected.url], pages: [redirected], issues: issues)

    assert_empty issues.to_a
  end

  def test_keeps_canonical_mismatch_for_a_page_outside_the_sitemap
    mismatched = page(body: '<html><head><link rel="canonical" href="https://example.com/preferred"></head></html>')
    issues = Crawlscope::IssueCollection.new

    Crawlscope::Rules::Metadata.new.call(urls: [], pages: [mismatched], issues: issues)

    canonical_issues = issues.select { |issue| [:canonical_mismatch, :non_canonical_page_in_sitemap].include?(issue.code) }
    assert_equal [:canonical_mismatch], canonical_issues.map(&:code)
    assert_equal "https://example.com/preferred", canonical_issues.first.details[:canonical]
  end

  private

  def page(url: "https://example.com/about", body: nil, final_url: url)
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
      final_url: final_url,
      normalized_final_url: Crawlscope::Url.normalize(final_url, base_url: url),
      status: 200,
      headers: {"content-type" => "text/html"},
      body: body,
      doc: Nokogiri::HTML(body)
    )
  end
end
