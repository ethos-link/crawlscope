# frozen_string_literal: true

require "test_helper"

class CrawlscopeCrawlerTest < Minitest::Test
  class RaisingFetcher
    def fetch(url)
      raise Timeout::Error, "fetch timed out" if url.include?("timeout")

      Crawlscope::Page.new(
        url: url,
        normalized_url: url,
        final_url: url,
        normalized_final_url: url,
        status: 200,
        headers: {},
        body: "<html></html>",
        doc: Nokogiri::HTML("<html></html>")
      )
    end
  end

  def test_returns_error_page_when_fetcher_raises
    pages = Crawlscope::Crawler.new(page_fetcher: RaisingFetcher.new, concurrency: 2).call(
      ["https://example.com/ok", "https://example.com/timeout"]
    )

    assert_equal 2, pages.size
    error_page = pages.find { |page| page.url == "https://example.com/timeout" }

    assert_nil error_page.status
    assert_equal "Timeout::Error: fetch timed out", error_page.error
  end
end
