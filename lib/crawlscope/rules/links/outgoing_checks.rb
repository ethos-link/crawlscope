# frozen_string_literal: true

module Crawlscope
  module Rules
    class Links
      class OutgoingChecks
        def initialize(base_url:, targets:, allowed_statuses:, scope:)
          @base_url = base_url
          @targets = targets
          @allowed_statuses = allowed_statuses
          @scope = scope
        end

        def call(urls:, pages:, links:, resolved_links:, issues:)
          validate_nofollow_outgoing_links(resolved_links, issues)
          validate_http_internal_links(links, issues)
          validate_pages_with_no_outgoing_links(urls, pages, links, issues)
          validate_indexable_pages_missing_from_sitemap(urls, resolved_links, issues)
        end

        private

        def validate_nofollow_outgoing_links(links, issues)
          links.select do |link|
            link[:nofollow] && link[:source_url] != link[:final_url] && !@targets.fetch(link[:target_url]).noindex?
          end.group_by { |link| link[:source_url] }.each do |source_url, grouped_links|
            target_urls = grouped_links.map { |link| link[:target_url] }.uniq

            issues.add(
              code: :nofollow_internal_outlinks,
              severity: :warning,
              category: :links,
              url: source_url,
              message: "page has nofollow outgoing internal links",
              details: {target_urls: target_urls}
            )
          end
        end

        def validate_http_internal_links(links, issues)
          links.select { |link| link[:http_internal_link] }.group_by { |link| link[:source_url] }.each do |source_url, grouped_links|
            target_urls = grouped_links.map { |link| link[:target_url] }.uniq

            issues.add(
              code: :http_internal_link,
              severity: :warning,
              category: :links,
              url: source_url,
              message: "HTTPS page links to internal HTTP URL",
              details: {target_urls: target_urls}
            )
          end
        end

        def validate_pages_with_no_outgoing_links(urls, pages, links, issues)
          sitemap_urls = urls.map { |url| Url.normalize(url, base_url: @base_url) }.compact.to_set
          return if sitemap_urls.size < 2

          source_paths_with_links = links.map { |link| link[:source_path] }.to_set

          pages.each do |page|
            next unless page.html?
            next unless sitemap_urls.include?(page.normalized_url)

            source_path = Url.path(page.normalized_url)
            next unless @scope.crawlable_source_path?(source_path)
            next if source_paths_with_links.include?(source_path)

            issues.add(
              code: :page_has_no_outgoing_links,
              severity: :warning,
              category: :links,
              url: page.url,
              message: "page has no outgoing internal links",
              details: {}
            )
          end
        end

        def validate_indexable_pages_missing_from_sitemap(urls, resolved_links, issues)
          sitemap_urls = urls.map { |url| Url.normalize(url, base_url: @base_url) }.compact.to_set
          resolved_links.group_by { |link| link[:final_url] }.each do |final_url, grouped_links|
            link = grouped_links.first
            next if sitemap_urls.include?(final_url)
            next unless @scope.crawlable_path?(link[:final_path])

            target = @targets.fetch(final_url)
            next unless target.allowed?(@allowed_statuses) && target.html?
            next if target.noindex?

            issues.add(
              code: :indexable_page_missing_from_sitemap,
              severity: :warning,
              category: :sitemaps,
              url: final_url,
              message: "linked page is missing from sitemap",
              details: {source_url: link[:source_url], source_urls: grouped_links.map { |entry| entry[:source_url] }.uniq}
            )
          end
        end
      end
    end
  end
end
