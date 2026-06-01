# frozen_string_literal: true

require "test_helper"

class CrawlscopeFetchExecutorTest < Minitest::Test
  class RecordingExecutor
    attr_reader :items

    def call(items)
      @items = items
      items.map { |item| yield(item) }
    end
  end

  def test_map_preserves_input_order
    results = Crawlscope::FetchExecutor.map(name: :threaded, concurrency: 2, items: [3, 1, 2]) do |item|
      item * 10
    end

    assert_equal [30, 10, 20], results
  end

  def test_map_uses_sequential_fallback_for_single_item
    executor = RecordingExecutor.new

    results = Crawlscope::FetchExecutor.map(name: executor, concurrency: 4, items: ["one"]) do |item|
      item.upcase
    end

    assert_equal ["ONE"], results
    assert_nil executor.items
  end

  def test_map_uses_injected_executor_for_parallel_work
    executor = RecordingExecutor.new

    results = Crawlscope::FetchExecutor.map(name: executor, concurrency: 4, items: %w[a b]) do |item|
      item.upcase
    end

    assert_equal %w[A B], results
    assert_equal %w[a b], executor.items
  end
end
