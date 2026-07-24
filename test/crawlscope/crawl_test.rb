# frozen_string_literal: true

require "test_helper"

class CrawlscopeCrawlTest < Minitest::Test
  class RecordingExecutor
    attr_reader :batches

    def initialize
      @batches = []
    end

    def call(urls)
      @batches << urls
      urls.map { |url| yield(url) }
    end
  end

  class PageMapFetcher
    attr_reader :closed

    def initialize(pages)
      @pages = pages
      @closed = false
    end

    def close
      @closed = true
    end

    def fetch(url)
      @pages.fetch(url)
    end
  end

  def setup
    @tmp_dir = Dir.mktmpdir
    @sitemap_path = File.join(@tmp_dir, "sitemap.xml")
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_http_renderer_defaults_to_async_executor
    crawl = Crawlscope::Crawl.new(
      base_url: "https://example.com",
      sitemap_path: @sitemap_path,
      rules: [],
      schema_registry: Crawlscope::SchemaRegistry.default
    )

    assert_equal :async, crawl.instance_variable_get(:@fetch_executor)
  end

  def test_browser_renderer_defaults_to_threaded_executor
    crawl = Crawlscope::Crawl.new(
      base_url: "https://example.com",
      sitemap_path: @sitemap_path,
      rules: [],
      schema_registry: Crawlscope::SchemaRegistry.default,
      renderer: :browser
    )

    assert_equal :threaded, crawl.instance_variable_get(:@fetch_executor)
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
              <meta name="description" content="Plans for hotels and restaurants that need practical software checks, clear metadata, and dependable search previews.">
              <link rel="canonical" href="https://example.com/pricing">
              <meta property="og:title" content="Pricing">
              <meta property="og:description" content="Plans for hotels and restaurants that need practical software checks, clear metadata, and dependable search previews.">
              <meta property="og:url" content="https://example.com/pricing">
              <meta property="og:type" content="website">
              <meta property="og:image" content="https://example.com/icon.png">
              <script type="application/ld+json">
                {"@context":"https://schema.org","@type":"WebSite","name":"Example","url":"https://example.com"}
              </script>
            </head>
            <body>
              <main>
                <h1>Pricing</h1>
                <p>#{Array.new(260) { |index| "pricing#{index}" }.join(" ")}</p>
              </main>
            </body>
          </html>
        HTML
      )

    result = Crawlscope::Crawl.new(
      base_url: "https://example.com",
      sitemap_path: @sitemap_path,
      rules: Crawlscope::RuleRegistry.default(site_name: "Example").rules,
      schema_registry: Crawlscope::SchemaRegistry.default,
      fetch_executor: :threaded
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
      schema_registry: Crawlscope::SchemaRegistry.default,
      fetch_executor: :threaded
    ).call

    assert result.ok?
    assert_equal %i[
      incomplete_open_graph_tags
      meta_description_too_long
      missing_canonical
      missing_h1
      missing_structured_data
      thin_visible_text
      title_repeats_site_name
    ].sort, result.issues.to_a.map(&:code).uniq.sort
  end

  def test_profile_token_reaches_remote_sitemap_and_page_requests
    sitemap_request = stub_request(:get, "https://example.com/sitemap.xml")
      .with(headers: {"X-Profile-Token" => "profile-token"})
      .to_return(
        status: 200,
        body: <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>https://example.com/about</loc></url>
          </urlset>
        XML
      )
    page_request = stub_request(:get, "https://example.com/about")
      .with(headers: {"X-Profile-Token" => "profile-token"})
      .to_return(status: 200, body: "<html><body>About</body></html>")

    Crawlscope::Crawl.new(
      base_url: "https://example.com",
      sitemap_path: "https://example.com/sitemap.xml",
      rules: [],
      schema_registry: Crawlscope::SchemaRegistry.default,
      fetch_executor: :threaded,
      profile_token: "profile-token"
    ).call

    assert_requested sitemap_request
    assert_requested page_request
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
              <meta name="description" content="Plans for hotels and restaurants that need practical software checks, clear metadata, and dependable search previews.">
              <link rel="canonical" href="https://example.com/pricing">
              <meta property="og:title" content="Pricing">
              <meta property="og:description" content="Plans for hotels and restaurants that need practical software checks, clear metadata, and dependable search previews.">
              <meta property="og:url" content="https://example.com/pricing">
              <meta property="og:type" content="website">
              <meta property="og:image" content="https://example.com/icon.png">
              <script type="application/ld+json">
                {"@context":"https://schema.org","@type":"WebSite","name":"Example","url":"https://example.com"}
              </script>
            </head>
            <body>
              <main>
                <h1>Pricing</h1>
                <p>#{Array.new(260) { |index| "pricing#{index}" }.join(" ")}</p>
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

  def test_async_executor_requires_http_renderer
    File.write(
      @sitemap_path,
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>https://example.com/pricing</loc></url>
        </urlset>
      XML
    )

    error = assert_raises(Crawlscope::ConfigurationError) do
      Crawlscope::Crawl.new(
        base_url: "https://example.com",
        sitemap_path: @sitemap_path,
        rules: [],
        schema_registry: Crawlscope::SchemaRegistry.default,
        renderer: :browser,
        fetch_executor: :async
      ).call
    end

    assert_equal "Async fetch execution is only supported with http rendering", error.message
  end

  def test_reports_sitemap_redirect_url
    File.write(
      @sitemap_path,
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>https://example.com/old</loc></url>
        </urlset>
      XML
    )

    stub_request(:get, "https://example.com/old")
      .to_return(status: 301, headers: {"Location" => "https://example.com/new"}, body: "")
    stub_request(:get, "https://example.com/new")
      .to_return(status: 200, headers: {"Content-Type" => "text/html"}, body: "<html><body>Moved</body></html>")

    result = Crawlscope::Crawl.new(
      base_url: "https://example.com",
      sitemap_path: @sitemap_path,
      rules: [],
      schema_registry: Crawlscope::SchemaRegistry.default,
      fetch_executor: :threaded
    ).call

    assert_includes result.issues.to_a.map(&:code), :sitemap_redirect_url
  end

  def test_resolves_uncrawled_link_targets_as_a_bounded_batch
    File.write(
      @sitemap_path,
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>https://example.com/guide</loc></url>
        </urlset>
      XML
    )

    executor = RecordingExecutor.new
    fetcher = PageMapFetcher.new(
      "https://example.com/guide" => page(
        "https://example.com/guide",
        "<main><a href=\"/one\">One</a><a href=\"/two\">Two</a></main>"
      ),
      "https://example.com/one" => page("https://example.com/one", "<main>One</main>"),
      "https://example.com/two" => page("https://example.com/two", "<main>Two</main>")
    )

    Crawlscope::Crawl.new(
      base_url: "https://example.com",
      sitemap_path: @sitemap_path,
      rules: [Crawlscope::Rules::Links.new],
      schema_registry: Crawlscope::SchemaRegistry.default,
      renderer: :browser,
      browser_factory: -> { fetcher },
      fetch_executor: executor,
      concurrency: 2
    ).call

    assert_equal(
      [
        ["https://example.com/guide"],
        ["https://example.com/one", "https://example.com/two"]
      ],
      executor.batches
    )
    assert fetcher.closed
  end

  private

  def page(url, body)
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
