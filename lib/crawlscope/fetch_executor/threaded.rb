# frozen_string_literal: true

require "concurrent"

module Crawlscope
  module FetchExecutor
    class Threaded
      def initialize(concurrency:)
        @concurrency = concurrency
      end

      def call(urls)
        indexed_urls = Array(urls).each_with_index.to_a
        pages = Array.new(indexed_urls.size)
        mutex = Mutex.new
        pool = Concurrent::FixedThreadPool.new(@concurrency)

        indexed_urls.each do |url, index|
          pool.post do
            page = yield(url)
            mutex.synchronize { pages[index] = page }
          end
        end

        pool.shutdown
        pool.wait_for_termination

        pages
      end
    end
  end
end
