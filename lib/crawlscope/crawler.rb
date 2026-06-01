# frozen_string_literal: true

module Crawlscope
  class Crawler
    def initialize(page_fetcher:, concurrency:, fetch_executor: :threaded)
      @page_fetcher = page_fetcher
      @fetch_executor = FetchExecutor.build(name: fetch_executor, concurrency: concurrency)
    end

    def call(urls)
      @fetch_executor.call(urls) { |url| fetch(url) }
    end

    private

    def fetch(url)
      @page_fetcher.fetch(url)
    rescue => error
      Page.new(
        url: url,
        normalized_url: Url.normalize(url, base_url: url),
        final_url: url,
        normalized_final_url: Url.normalize(url, base_url: url),
        status: nil,
        headers: {},
        body: nil,
        doc: nil,
        error: "#{error.class}: #{error.message}"
      )
    end
  end
end
