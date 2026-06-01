# frozen_string_literal: true

require "async"
require "async/semaphore"

module Crawlscope
  module FetchExecutor
    class Async
      def initialize(concurrency:)
        @concurrency = concurrency
      end

      def call(urls)
        indexed_urls = Array(urls).each_with_index.to_a
        pages = Array.new(indexed_urls.size)

        Sync do |parent|
          semaphore = ::Async::Semaphore.new(@concurrency)
          tasks = indexed_urls.map do |url, index|
            semaphore.async(parent: parent) do
              pages[index] = yield(url)
            end
          end

          tasks.each(&:wait)
        end

        pages
      end
    end
  end
end
