# frozen_string_literal: true

module Crawlscope
  module Rules
    class Links
      class InboundChecks
        def initialize(base_url:, graph:, scope:)
          @base_url = base_url
          @graph = graph
          @scope = scope
        end

        def call(urls:, pages:, issues:)
          sitemap_urls = urls.filter_map do |url|
            normalized_url = Url.normalize(url, base_url: @base_url)
            path = Url.path(normalized_url)
            next if path.nil?
            next if @scope.skip_internal_path?(path)

            normalized_url
          end.to_set
          return if sitemap_urls.size < 2

          html_urls = pages.each_with_object(Set.new) do |page, result|
            next unless page.html?

            [page.normalized_url, page.normalized_final_url].compact.each do |url|
              path = Url.path(url)
              next if path.nil?
              next if @scope.skip_internal_path?(path)

              result << url
            end
          end

          sitemap_urls.each do |target_url|
            next unless html_urls.include?(target_url)

            inbound_count = @graph.inbound_count(target_url)
            dofollow_count = @graph.dofollow_count(target_url)
            nofollow_count = @graph.nofollow_count(target_url)

            report_orphan_page(target_url, issues) if inbound_count.zero?

            if inbound_count.positive? && inbound_count < MIN_INBOUND_ANCHOR_LINKS
              source_samples = @graph.sources(target_url)

              issues.add(
                code: :low_inbound_anchor_links,
                severity: :warning,
                category: :links,
                url: target_url,
                message: "incoming internal links: #{inbound_count}; minimum #{MIN_INBOUND_ANCHOR_LINKS}",
                details: {inbound_count: inbound_count, minimum: MIN_INBOUND_ANCHOR_LINKS, source_urls: source_samples}
              )
            end

            report_low_dofollow_inlinks(target_url, dofollow_count, @graph.sources(target_url, nofollow: false), issues)
            report_only_nofollow_internal_inlinks(target_url, nofollow_count, dofollow_count, @graph.sources(target_url, nofollow: true), issues)
            report_mixed_follow_internal_inlinks(target_url, nofollow_count, dofollow_count, @graph.sources(target_url, nofollow: true), @graph.sources(target_url, nofollow: false), issues)
          end
        end

        private

        def report_orphan_page(target_url, issues)
          issues.add(
            code: :orphan_page,
            severity: :warning,
            category: :links,
            url: target_url,
            message: "page has no incoming internal links",
            details: {}
          )
        end

        def report_low_dofollow_inlinks(target_url, dofollow_count, source_samples, issues)
          return if dofollow_count.zero?
          return if dofollow_count >= MIN_DOFOLLOW_INBOUND_LINKS

          issues.add(
            code: :low_dofollow_inlinks,
            severity: :warning,
            category: :links,
            url: target_url,
            message: "incoming internal links without nofollow: #{dofollow_count}; minimum #{MIN_DOFOLLOW_INBOUND_LINKS}",
            details: {dofollow_inbound_count: dofollow_count, minimum: MIN_DOFOLLOW_INBOUND_LINKS, source_urls: source_samples}
          )
        end

        def report_only_nofollow_internal_inlinks(target_url, nofollow_count, dofollow_count, nofollow_sources, issues)
          return unless nofollow_count.positive? && dofollow_count.zero?

          issues.add(
            code: :only_nofollow_internal_inlinks,
            severity: :warning,
            category: :links,
            url: target_url,
            message: "all incoming internal links use nofollow",
            details: {nofollow_inbound_count: nofollow_count, source_urls: nofollow_sources}
          )
        end

        def report_mixed_follow_internal_inlinks(target_url, nofollow_count, dofollow_count, nofollow_sources, dofollow_sources, issues)
          return unless nofollow_count.positive? && dofollow_count.positive?

          issues.add(
            code: :mixed_follow_internal_inlinks,
            severity: :notice,
            category: :links,
            url: target_url,
            message: "page has nofollow and dofollow incoming internal links",
            details: {
              dofollow_inbound_count: dofollow_count,
              nofollow_inbound_count: nofollow_count,
              dofollow_source_urls: dofollow_sources,
              nofollow_source_urls: nofollow_sources
            }
          )
        end
      end
    end
  end
end
