# frozen_string_literal: true

require "test_helper"

class CrawlscopeCrawlTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    @sitemap_path = File.join(@tmp_dir, "sitemap.xml")
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_returns_ok_when_metadata_is_valid
    File.write(
      @sitemap_path,
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>https://example.com/pricing</loc></url>
        </urlset>
      XML
    )

    stub_request(:get, "https://example.com/pricing")
      .to_return(
        status: 200,
        headers: {"Content-Type" => "text/html"},
        body: <<~HTML
          <html>
            <head>
              <title>Pricing</title>
              <meta name="description" content="Plans for hotels and restaurants">
              <link rel="canonical" href="https://example.com/pricing">
              <script type="application/ld+json">
                {"@context":"https://schema.org","@type":"WebSite","name":"Example","url":"https://example.com"}
              </script>
            </head>
            <body>
              <main>
                <h1>Pricing</h1>
              </main>
            </body>
          </html>
        HTML
      )

    result = Crawlscope::Crawl.new(
      base_url: "https://example.com",
      sitemap_path: @sitemap_path,
      rules: Crawlscope::RuleRegistry.default(site_name: "Example").rules,
      schema_registry: Crawlscope::SchemaRegistry.default
    ).call

    assert result.ok?
    assert_empty result.issues.to_a
  end

  def test_collects_metadata_issues_for_invalid_page
    File.write(
      @sitemap_path,
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>https://example.com/about</loc></url>
        </urlset>
      XML
    )

    stub_request(:get, "https://example.com/about")
      .to_return(
        status: 200,
        headers: {"Content-Type" => "text/html"},
        body: <<~HTML
          <html>
            <head>
              <title>Example About Example</title>
              <meta name="description" content="#{"a" * 161}">
            </head>
            <body>
              <main>
                <p>About</p>
              </main>
            </body>
          </html>
        HTML
      )

    result = Crawlscope::Crawl.new(
      base_url: "https://example.com",
      sitemap_path: @sitemap_path,
      rules: Crawlscope::RuleRegistry.default(site_name: "Example").rules,
      schema_registry: Crawlscope::SchemaRegistry.default
    ).call

    refute result.ok?
    assert_equal %i[meta_description_too_long missing_canonical missing_h1 missing_structured_data title_repeats_site_name].sort, result.issues.to_a.map(&:code).uniq.sort
  end

  def test_uses_browser_when_renderer_is_browser
    File.write(
      @sitemap_path,
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>https://example.com/pricing</loc></url>
        </urlset>
      XML
    )

    fake_browser = Class.new do
      attr_reader :closed, :urls

      def initialize
        @closed = false
        @urls = []
      end

      def close
        @closed = true
      end

      def fetch(url)
        @urls << url

        body = <<~HTML
          <html>
            <head>
              <title>Pricing</title>
              <meta name="description" content="Plans for hotels and restaurants">
              <link rel="canonical" href="https://example.com/pricing">
              <script type="application/ld+json">
                {"@context":"https://schema.org","@type":"WebSite","name":"Example","url":"https://example.com"}
              </script>
            </head>
            <body>
              <main>
                <h1>Pricing</h1>
              </main>
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
    end.new

    result = Crawlscope::Crawl.new(
      base_url: "https://example.com",
      sitemap_path: @sitemap_path,
      rules: Crawlscope::RuleRegistry.default(site_name: "Example").rules,
      schema_registry: Crawlscope::SchemaRegistry.default,
      renderer: :browser,
      browser_factory: -> { fake_browser }
    ).call

    assert result.ok?
    assert_equal ["https://example.com/pricing"], fake_browser.urls
    assert fake_browser.closed
  end
end
