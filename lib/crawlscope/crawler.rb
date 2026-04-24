# frozen_string_literal: true

require "concurrent"

module Crawlscope
  class Crawler
    def initialize(page_fetcher:, concurrency:)
      @page_fetcher = page_fetcher
      @concurrency = concurrency
    end

    def call(urls)
      pages = Concurrent::Array.new
      pool = Concurrent::FixedThreadPool.new(@concurrency)

      urls.each do |url|
        pool.post do
          pages << fetch(url)
        end
      end

      pool.shutdown
      pool.wait_for_termination

      pages.to_a
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
