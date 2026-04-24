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

    assert_equal [:broken_internal_link], issues.to_a.map(&:code)
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

    assert_equal [:low_inbound_anchor_links], issues.to_a.map(&:code)
    assert_equal "https://example.com/guide", issues.to_a.first.url
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
        status: 200
      }
    when "https://example.com/missing"
      {
        crawled: false,
        error: nil,
        final_url: target_url,
        status: 404
      }
    end
  end
end
