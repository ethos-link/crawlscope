# frozen_string_literal: true

require "test_helper"

class CrawlscopeSitemapTest < Minitest::Test
  class RecordingExecutor
    attr_reader :batches

    def initialize
      @batches = []
    end

    def call(items)
      @batches << items
      items.map { |item| yield(item) }
    end
  end

  def test_parses_remote_sitemap_urlset
    stub_request(:get, "https://www.example.com/sitemap.xml")
      .to_return(
        status: 200,
        body: <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>https://www.example.com/</loc></url>
            <url><loc>/pricing</loc></url>
          </urlset>
        XML
      )

    parser = Crawlscope::Sitemap.new(path: "https://www.example.com/sitemap.xml")

    assert_equal ["https://www.example.com/", "https://www.example.com/pricing"], parser.urls(base_url: "https://www.example.com")
  end

  def test_parses_remote_sitemap_index_with_child_sitemap
    stub_request(:get, "https://www.example.com/sitemap.xml")
      .to_return(
        status: 200,
        body: <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <sitemap><loc>/sitemaps/content.xml</loc></sitemap>
          </sitemapindex>
        XML
      )

    stub_request(:get, "https://www.example.com/sitemaps/content.xml")
      .to_return(
        status: 200,
        body: <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>https://www.example.com/features/reviews</loc></url>
          </urlset>
        XML
      )

    parser = Crawlscope::Sitemap.new(path: "https://www.example.com/sitemap.xml")

    assert_equal ["https://www.example.com/features/reviews"], parser.urls(base_url: "https://www.example.com")
  end

  def test_remote_sitemap_http_error_is_explicit
    stub_request(:get, "https://www.example.com/sitemap.xml")
      .to_return(status: 500, body: "<html><body>Error</body></html>")

    parser = Crawlscope::Sitemap.new(path: "https://www.example.com/sitemap.xml")

    error = assert_raises(Crawlscope::ValidationError) do
      parser.urls(base_url: "https://www.example.com")
    end
    assert_equal "Sitemap https://www.example.com/sitemap.xml returned HTTP 500", error.message
  end

  def test_invalid_sitemap_root_is_explicit
    stub_request(:get, "https://www.example.com/sitemap.xml")
      .to_return(status: 200, body: "<html><body>Error</body></html>")

    parser = Crawlscope::Sitemap.new(path: "https://www.example.com/sitemap.xml")

    error = assert_raises(Crawlscope::ValidationError) do
      parser.urls(base_url: "https://www.example.com")
    end
    assert_equal 'Sitemap https://www.example.com/sitemap.xml has unexpected root "html"', error.message
  end

  def test_rebases_remote_sitemap_index_children_to_base_url
    stub_request(:get, "http://localhost:3000/sitemap.xml")
      .to_return(
        status: 200,
        body: <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <sitemap><loc>https://www.example.com/sitemap-marketing.xml</loc></sitemap>
          </sitemapindex>
        XML
      )

    stub_request(:get, "http://localhost:3000/sitemap-marketing.xml")
      .to_return(
        status: 200,
        body: <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>https://www.example.com/features/reviews</loc></url>
          </urlset>
        XML
      )

    parser = Crawlscope::Sitemap.new(path: "http://localhost:3000/sitemap.xml")

    assert_equal ["http://localhost:3000/features/reviews"], parser.urls(base_url: "http://localhost:3000")
  end

  def test_parses_local_sitemap_index_with_absolute_child_sitemap_loc
    Dir.mktmpdir do |dir|
      File.write(
        File.join(dir, "sitemap.xml"),
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <sitemap><loc>https://www.example.com/sitemap-pages.xml</loc></sitemap>
          </sitemapindex>
        XML
      )
      File.write(
        File.join(dir, "sitemap-pages.xml"),
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>https://www.example.com/features/reviews</loc></url>
          </urlset>
        XML
      )

      parser = Crawlscope::Sitemap.new(path: File.join(dir, "sitemap.xml"))

      assert_equal ["http://localhost:3000/features/reviews"], parser.urls(base_url: "http://localhost:3000")
    end
  end

  def test_child_sitemaps_are_collected_through_the_fetch_executor
    Dir.mktmpdir do |dir|
      File.write(
        File.join(dir, "sitemap.xml"),
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <sitemap><loc>first.xml</loc></sitemap>
            <sitemap><loc>second.xml</loc></sitemap>
          </sitemapindex>
        XML
      )
      File.write(
        File.join(dir, "first.xml"),
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>http://localhost:3000/first</loc></url>
          </urlset>
        XML
      )
      File.write(
        File.join(dir, "second.xml"),
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>http://localhost:3000/second</loc></url>
          </urlset>
        XML
      )

      executor = RecordingExecutor.new
      parser = Crawlscope::Sitemap.new(path: File.join(dir, "sitemap.xml"), fetch_executor: executor)

      assert_equal ["http://localhost:3000/first", "http://localhost:3000/second"], parser.urls(base_url: "http://localhost:3000")
      assert_equal [[File.join(dir, "first.xml"), File.join(dir, "second.xml")]], executor.batches
    end
  end
end
