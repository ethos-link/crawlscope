# frozen_string_literal: true

module Crawlscope
  module Rules
    class Links
      class Graph
        def initialize(links:, targets:)
          @incoming = links.reject do |link|
            link[:source_url] == link[:final_url] || targets.fetch(link[:target_url]).noindex?
          end.group_by { |link| link[:final_url] }
        end

        def inbound_count(url)
          incoming(url).size
        end

        def dofollow_count(url)
          incoming(url).count { |link| !link[:nofollow] }
        end

        def nofollow_count(url)
          incoming(url).count { |link| link[:nofollow] }
        end

        def sources(url, nofollow: nil)
          incoming(url).filter_map do |link|
            link[:source_url] if nofollow.nil? || link[:nofollow] == nofollow
          end.uniq
        end

        private

        def incoming(url)
          @incoming.fetch(url, [])
        end
      end
    end
  end
end
