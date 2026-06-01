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

  def test_preserves_input_order
    pages = Crawlscope::Crawler.new(page_fetcher: RaisingFetcher.new, concurrency: 2).call(
      ["https://example.com/one", "https://example.com/two", "https://example.com/three"]
    )

    assert_equal(
      ["https://example.com/one", "https://example.com/two", "https://example.com/three"],
      pages.map(&:url)
    )
  end

  class AsyncFetcher
    attr_reader :active_fetches

    def initialize
      @active_fetches = 0
      @max_active_fetches = 0
      @mutex = Mutex.new
    end

    def fetch(url)
      @mutex.synchronize do
        @active_fetches += 1
        @max_active_fetches = [@max_active_fetches, @active_fetches].max
      end

      Async::Task.current.sleep(0.01)

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
    ensure
      @mutex.synchronize { @active_fetches -= 1 }
    end

    def max_active_fetches
      @mutex.synchronize { @max_active_fetches }
    end
  end

  def test_async_executor_respects_concurrency_and_preserves_order
    fetcher = AsyncFetcher.new

    pages = Crawlscope::Crawler.new(page_fetcher: fetcher, concurrency: 2, fetch_executor: :async).call(
      ["https://example.com/one", "https://example.com/two", "https://example.com/three"]
    )

    assert_equal(
      ["https://example.com/one", "https://example.com/two", "https://example.com/three"],
      pages.map(&:url)
    )
    assert_operator fetcher.max_active_fetches, :<=, 2
  end
end
