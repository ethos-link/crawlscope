# frozen_string_literal: true

module Crawlscope
  module Rules
    class Links
      class TargetLookup
        def initialize(context:)
          @resolve_target = context.fetch(:resolve_target)
          @resolve_targets = if context.respond_to?(:resolve_targets)
            context.resolve_targets
          elsif context.respond_to?(:[])
            context[:resolve_targets]
          end
          @targets = {}
        end

        def resolve_all(urls)
          missing = urls.uniq.reject { |url| @targets.key?(url) }
          return if missing.empty?

          if @resolve_targets
            @resolve_targets.call(missing).each do |url, resolution|
              @targets[url] = Crawling::Target.new(target_url: url, resolution: resolution)
            end
          else
            missing.each { |url| fetch(url) }
          end
        end

        def fetch(url)
          @targets.fetch(url) do
            @targets[url] = Crawling::Target.new(target_url: url, resolution: @resolve_target.call(url))
          end
        end
      end
    end
  end
end
