# frozen_string_literal: true

require "test_helper"

class CrawlscopeLinksRuleTest < Minitest::Test
  def test_reports_broken_internal_links
    issues = Crawlscope::IssueCollection.new
    rule = Crawlscope::Rules::Links.new
    pages = [
      page(
        url: "https://example.com/guide",
        body: <<~HTML
          <html>
            <body>
              <main>
                <a href="/pricing">Pricing</a>
                <a href="/missing">Missing</a>
              </main>
            </body>
          </html>
        HTML
      ),
      page(
        url: "https://example.com/pricing",
        body: <<~HTML
          <html>
            <body>
              <main>
                <a href="/guide">Guide</a>
              </main>
            </body>
          </html>
        HTML
      )
    ]

    rule.call(
      urls: ["https://example.com/guide", "https://example.com/pricing"],
      pages: pages,
      issues: issues,
      context: context
    )

    assert_includes issues.to_a.map(&:code), :broken_internal_link
    assert_includes issues.to_a.first.message, "HTTP 404"
  end

  def test_reports_unresolved_internal_links
    issues = Crawlscope::IssueCollection.new

    Crawlscope::Rules::Links.new.call(
      urls: [],
      pages: [page(url: "https://example.com/guide", body: "<main><a href=\"/unknown\">Unknown</a></main>")],
      issues: issues,
      context: context(resolver: ->(_target_url) {})
    )

    assert_includes issues.to_a.map(&:code), :unresolved_internal_link
    assert_includes issues.to_a.find { |issue| issue.code == :unresolved_internal_link }.message, "unable to validate internal link"
  end

  def test_ignores_fetch_errors_for_urls_already_crawled
    issues = Crawlscope::IssueCollection.new
    resolver = lambda do |target_url|
      {
        crawled: true,
        error: "Timeout::Error: timed out",
        final_url: target_url,
        status: nil
      }
    end

    Crawlscope::Rules::Links.new.call(
      urls: [],
      pages: [page(url: "https://example.com/guide", body: "<main><a href=\"/timeout\">Timeout</a></main>")],
      issues: issues,
      context: context(resolver: resolver)
    )

    assert_empty issues.to_a
  end

  def test_reports_fetch_errors_for_uncrawled_targets
    issues = Crawlscope::IssueCollection.new
    resolver = lambda do |target_url|
      {
        crawled: false,
        error: "Timeout::Error: timed out",
        final_url: target_url,
        status: nil
      }
    end

    Crawlscope::Rules::Links.new.call(
      urls: [],
      pages: [page(url: "https://example.com/guide", body: "<main><a href=\"/timeout\">Timeout</a></main>")],
      issues: issues,
      context: context(resolver: resolver)
    )

    assert_equal [:unresolved_internal_link], issues.to_a.map(&:code)
  end

  def test_reports_low_inbound_anchor_links
    issues = Crawlscope::IssueCollection.new

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/guide", "https://example.com/pricing"],
      pages: [
        page(url: "https://example.com/guide", body: "<main><a href=\"/pricing\">Pricing</a></main>"),
        page(url: "https://example.com/pricing", body: "<main><p>Pricing</p></main>")
      ],
      issues: issues,
      context: context
    )

    orphan_issue = issues.to_a.find { |item| item.code == :orphan_page }
    assert orphan_issue
    assert_includes issues.to_a.map(&:code), :low_dofollow_inlinks
    assert_equal "https://example.com/guide", orphan_issue.url
  end

  def test_reports_pages_with_no_outgoing_internal_links
    issues = Crawlscope::IssueCollection.new

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/guide", "https://example.com/pricing"],
      pages: [
        page(url: "https://example.com/guide", body: "<main><a href=\"/pricing\">Pricing</a></main>"),
        page(url: "https://example.com/pricing", body: "<main><p>Pricing</p></main>")
      ],
      issues: issues,
      context: context
    )

    issue = issues.to_a.find { |item| item.code == :page_has_no_outgoing_links }
    assert issue
    assert_equal "https://example.com/pricing", issue.url
  end

  def test_reports_nofollow_outlinks_and_inlink_follow_mix
    issues = Crawlscope::IssueCollection.new

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/guide", "https://example.com/pricing", "https://example.com/about"],
      pages: [
        page(url: "https://example.com/guide", body: "<main><a href=\"/pricing\" rel=\"nofollow\">Pricing</a><a href=\"/about\">About</a></main>"),
        page(url: "https://example.com/about", body: "<main><a href=\"/pricing\">Pricing</a></main>"),
        page(url: "https://example.com/pricing", body: "<main><p>Pricing</p></main>")
      ],
      issues: issues,
      context: context(resolver: ->(target_url) { {crawled: true, error: nil, final_url: target_url, status: 200} })
    )

    codes = issues.to_a.map(&:code)
    assert_includes codes, :nofollow_internal_outlinks
    assert_includes codes, :mixed_follow_internal_inlinks
  end

  def test_reports_only_nofollow_internal_inlinks
    issues = Crawlscope::IssueCollection.new

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/guide", "https://example.com/pricing"],
      pages: [
        page(url: "https://example.com/guide", body: "<main><a href=\"/pricing\" rel=\"nofollow\">Pricing</a></main>"),
        page(url: "https://example.com/pricing", body: "<main><p>Pricing</p></main>")
      ],
      issues: issues,
      context: context(resolver: ->(target_url) { {crawled: true, error: nil, final_url: target_url, status: 200} })
    )

    assert_includes issues.to_a.map(&:code), :only_nofollow_internal_inlinks
  end

  def test_reports_https_pages_linking_to_internal_http_urls
    issues = Crawlscope::IssueCollection.new

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/guide"],
      pages: [page(url: "https://example.com/guide", body: "<main><a href=\"http://example.com/pricing\">Pricing</a></main>")],
      issues: issues,
      context: context(resolver: ->(target_url) { {crawled: true, error: nil, final_url: target_url, status: 200} })
    )

    assert_includes issues.to_a.map(&:code), :http_internal_link
  end

  def test_reports_canonical_target_link_issues
    issues = Crawlscope::IssueCollection.new
    resolver = lambda do |target_url|
      redirects = target_url == "https://example.com/canonical-about"
      status = redirects ? 301 : 200
      final_url = redirects ? "https://example.com/about" : target_url
      {crawled: false, error: nil, final_url: final_url, status: status}
    end

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/guide", "https://example.com/about"],
      pages: [
        page(url: "https://example.com/guide", body: "<main><a href=\"/about\">About</a></main>"),
        page(
          url: "https://example.com/about",
          body: <<~HTML
            <html>
              <head><link rel="canonical" href="https://example.com/canonical-about"></head>
              <body><main><p>About</p></main></body>
            </html>
          HTML
        )
      ],
      issues: issues,
      context: context(resolver: resolver)
    )

    codes = issues.to_a.map(&:code)
    assert_includes codes, :canonical_no_internal_inlinks
    assert_includes codes, :canonical_points_to_redirect
  end

  def test_does_not_report_missing_inlinks_for_root_canonical
    issues = Crawlscope::IssueCollection.new
    resolver = lambda do |target_url|
      {crawled: true, error: nil, final_url: target_url, html: true, status: 200}
    end

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/", "https://example.com/about"],
      pages: [
        page(
          url: "https://example.com/",
          body: <<~HTML
            <html>
              <head><link rel="canonical" href="https://example.com/"></head>
              <body><main><a href="/about">About</a></main></body>
            </html>
          HTML
        ),
        page(url: "https://example.com/about", body: "<main><a href=\"/\">Home</a></main>")
      ],
      issues: issues,
      context: context(resolver: resolver)
    )

    refute_includes issues.to_a.map(&:code), :canonical_no_internal_inlinks
  end

  def test_reports_indexable_internal_pages_missing_from_sitemap
    issues = Crawlscope::IssueCollection.new
    resolver = lambda do |target_url|
      {
        crawled: false,
        error: nil,
        final_url: target_url,
        html: true,
        status: 200
      }
    end

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/guide"],
      pages: [page(url: "https://example.com/guide", body: "<main><a href=\"/hidden\">Hidden</a></main>")],
      issues: issues,
      context: context(resolver: resolver)
    )

    issue = issues.to_a.find { |item| item.code == :indexable_page_missing_from_sitemap }
    assert issue
    assert_equal "https://example.com/hidden", issue.url
  end

  def test_does_not_report_noindex_internal_pages_missing_from_sitemap
    issues = Crawlscope::IssueCollection.new
    resolver = lambda do |target_url|
      {
        crawled: false,
        doc: Nokogiri::HTML("<head><meta name=\"robots\" content=\"noindex, follow\"></head>"),
        error: nil,
        final_url: target_url,
        headers: {},
        html: true,
        status: 200
      }
    end

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/guide"],
      pages: [page(url: "https://example.com/guide", body: "<main><a href=\"/hidden\">Hidden</a></main>")],
      issues: issues,
      context: context(resolver: resolver)
    )

    refute_includes issues.to_a.map(&:code), :indexable_page_missing_from_sitemap
  end

  def test_does_not_report_x_robots_noindex_internal_pages_missing_from_sitemap
    issues = Crawlscope::IssueCollection.new
    resolver = lambda do |target_url|
      {
        crawled: false,
        doc: Nokogiri::HTML("<main>Hidden</main>"),
        error: nil,
        final_url: target_url,
        headers: {"X-Robots-Tag" => "noindex"},
        html: true,
        status: 200
      }
    end

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/guide"],
      pages: [page(url: "https://example.com/guide", body: "<main><a href=\"/hidden\">Hidden</a></main>")],
      issues: issues,
      context: context(resolver: resolver)
    )

    refute_includes issues.to_a.map(&:code), :indexable_page_missing_from_sitemap
  end

  def test_reports_url_hygiene_issues
    issues = Crawlscope::IssueCollection.new
    long_path = "a" * 2_050

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com//bad", "https://example.com/#{long_path}"],
      pages: [
        page(url: "https://example.com//bad", body: "<main><a href=\"/ok\">OK</a></main>"),
        page(url: "https://example.com/#{long_path}", body: "<main><a href=\"/ok\">OK</a></main>")
      ],
      issues: issues,
      context: context(resolver: ->(target_url) { {crawled: false, error: nil, final_url: target_url, html: true, status: 200} })
    )

    codes = issues.to_a.map(&:code)
    assert_includes codes, :url_double_slash
    assert_includes codes, :url_too_long
  end

  def test_counts_root_page_links_as_inbound_links
    issues = Crawlscope::IssueCollection.new

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/", "https://example.com/about"],
      pages: [
        page(url: "https://example.com/", body: "<main><a href=\"/about\">About</a></main>"),
        page(url: "https://example.com/about", body: "<main><p>About</p></main>")
      ],
      issues: issues,
      context: context(resolver: ->(target_url) { {crawled: true, error: nil, final_url: target_url, status: 200} })
    )

    refute_includes issues.to_a.map(&:code), :low_inbound_anchor_links
  end

  def test_reports_internal_links_that_redirect
    issues = Crawlscope::IssueCollection.new
    resolver = lambda do |target_url|
      {
        crawled: false,
        error: nil,
        final_url: "https://example.com/pricing",
        status: 200
      }
    end

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/guide"],
      pages: [page(url: "https://example.com/guide", body: "<main><a href=\"/plans\">Plans</a></main>")],
      issues: issues,
      context: context(resolver: resolver)
    )

    redirect_issue = issues.to_a.find { |issue| issue.code == :internal_link_redirects }
    assert redirect_issue
    assert_includes redirect_issue.message, "https://example.com/pricing"
  end

  def test_reuses_link_target_resolution_for_later_link_checks
    issues = Crawlscope::IssueCollection.new
    resolution_counts = Hash.new(0)
    resolver = lambda do |target_url|
      resolution_counts[target_url] += 1
      {
        crawled: false,
        doc: Nokogiri::HTML("<main>Hidden</main>"),
        error: nil,
        final_url: target_url,
        headers: {},
        html: true,
        status: 200
      }
    end

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/guide"],
      pages: [page(url: "https://example.com/guide", body: "<main><a href=\"/hidden\">Hidden</a></main>")],
      issues: issues,
      context: context(resolver: resolver)
    )

    assert_equal 1, resolution_counts.fetch("https://example.com/hidden")
  end

  def test_ignores_links_that_should_not_be_crawled
    issues = Crawlscope::IssueCollection.new

    Crawlscope::Rules::Links.new.call(
      urls: ["https://example.com/guide"],
      pages: [
        page(
          url: "https://example.com/guide",
          body: <<~HTML
            <html>
              <body>
                <a href="#section">Jump</a>
                <a href="mailto:test@example.com">Email</a>
                <a href="https://other.example.com/page">External</a>
                <a href="/rails/info">Rails</a>
                <a href="/empty">   </a>
              </body>
            </html>
          HTML
        )
      ],
      issues: issues,
      context: context
    )

    assert_empty issues.to_a
  end

  private

  def context(resolver: method(:resolve_target))
    {
      allowed_statuses: [200, 301, 302],
      base_url: "https://example.com",
      resolve_target: resolver
    }
  end

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

  def resolve_target(target_url)
    case target_url
    when "https://example.com/guide", "https://example.com/pricing"
      {
        crawled: true,
        error: nil,
        final_url: target_url,
        html: true,
        status: 200
      }
    when "https://example.com/missing"
      {
        crawled: false,
        error: nil,
        final_url: target_url,
        html: false,
        status: 404
      }
    end
  end
end
