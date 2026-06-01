# frozen_string_literal: true

require "concurrent"

module Crawlscope
  module FetchExecutor
    class Threaded
      def initialize(concurrency:)
        @concurrency = concurrency
      end

      def call(items)
        indexed_items = Array(items).each_with_index.to_a
        results = Array.new(indexed_items.size)
        mutex = Mutex.new
        pool = Concurrent::FixedThreadPool.new(@concurrency)

        indexed_items.each do |item, index|
          pool.post do
            result = yield(item)
            mutex.synchronize { results[index] = result }
          end
        end

        pool.shutdown
        pool.wait_for_termination

        results
      end
    end
  end
end
