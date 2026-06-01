# frozen_string_literal: true

module Crawlscope
  module FetchExecutor
    NAMES = %i[threaded async].freeze

    module_function

    def build(name:, concurrency:)
      return name if name.respond_to?(:call)

      case normalized_name(name)
      when :threaded
        Threaded.new(concurrency: concurrency)
      when :async
        Async.new(concurrency: concurrency)
      end
    end

    def map(name:, concurrency:, items:, &block)
      items = Array(items)
      return items.map(&block) if items.size < 2 || concurrency.to_i <= 1

      build(name: name, concurrency: concurrency).call(items, &block)
    end

    def normalize(name)
      return name if name.respond_to?(:call)

      normalized_name(name)
    end

    def normalized_name(name)
      normalized = name.to_s.strip
      normalized = "threaded" if normalized.empty?

      value = normalized.to_sym
      return value if NAMES.include?(value)

      raise ConfigurationError, "Crawlscope fetch_executor must be threaded or async"
    end
  end
end
