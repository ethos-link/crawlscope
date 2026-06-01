# frozen_string_literal: true

require "async"
require "async/semaphore"

module Crawlscope
  module FetchExecutor
    class Async
      def initialize(concurrency:)
        @concurrency = concurrency
      end

      def call(items)
        indexed_items = Array(items).each_with_index.to_a
        results = Array.new(indexed_items.size)

        Sync do |parent|
          semaphore = ::Async::Semaphore.new(@concurrency)
          tasks = indexed_items.map do |item, index|
            semaphore.async(parent: parent) do
              results[index] = yield(item)
            end
          end

          tasks.each(&:wait)
        end

        results
      end
    end
  end
end
