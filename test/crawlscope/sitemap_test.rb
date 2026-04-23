# frozen_string_literal: true

require "test_helper"

class CrawlscopeSitemapTest < Minitest::Test
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
end
