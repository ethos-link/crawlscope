# frozen_string_literal: true

module Crawlscope
  module Rules
    class Links
      class CanonicalChecks
        def initialize(base_url:, targets:, allowed_statuses:, graph:)
          @base_url = base_url
          @base_host = URI.parse(base_url).host
          @targets = targets
          @allowed_statuses = allowed_statuses
          @graph = graph
        end

        def call(urls:, pages:, issues:)
          sitemap_urls = urls.map { |url| Url.normalize(url, base_url: @base_url) }.compact
          sitemap_pages = pages.select do |page|
            page.html? && sitemap_urls.include?(page.normalized_url) && page.normalized_url.to_s == page.normalized_final_url.to_s
          end
          return if sitemap_pages.size < 2

          canonical_entries = canonical_entries_for(sitemap_pages)
          @targets.resolve_all(canonical_entries.map { |entry| entry.fetch(:canonical_url) })

          canonical_entries.each do |entry|
            page = entry.fetch(:page)
            canonical_url = entry.fetch(:canonical_url)
            canonical_path = entry.fetch(:canonical_path)
            if canonical_path && !root_path?(canonical_path) && @graph.dofollow_count(canonical_url).zero?
              issues.add(
                code: :canonical_no_internal_inlinks,
                severity: :warning,
                category: :links,
                url: canonical_url,
                message: "canonical URL has no incoming internal links without nofollow",
                details: {source_url: page.url}
              )
            end

            validate_canonical_target_status(page, canonical_url, issues)
          end
        end

        private

        def canonical_entries_for(pages)
          pages.filter_map do |page|
            canonical_url = canonical_url_for(page)
            next if canonical_url.nil?

            target_uri = URI.parse(canonical_url)
            next if target_uri.host != @base_host

            {
              canonical_path: Url.path(canonical_url),
              canonical_url: canonical_url,
              page: page
            }
          rescue URI::InvalidURIError
            nil
          end
        end

        def canonical_url_for(page)
          page.canonical.url
        end

        def root_path?(path)
          path == "/"
        end

        def validate_canonical_target_status(page, canonical_url, issues)
          target = @targets.fetch(canonical_url)

          if target.unresolved? || target.ignored_error?
            return
          end

          if target.redirect?
            issues.add(
              code: :canonical_points_to_redirect,
              severity: :warning,
              category: :metadata,
              url: page.url,
              message: "canonical #{canonical_url} redirects to #{target.final_url}",
              details: {canonical: canonical_url, final_url: target.final_url, status: target.status}
            )
          elsif !target.allowed?(@allowed_statuses)
            issues.add(
              code: :canonical_points_to_error,
              severity: :warning,
              category: :metadata,
              url: page.url,
              message: "canonical #{canonical_url} returns HTTP #{target.status}",
              details: {canonical: canonical_url, status: target.status}
            )
          end
        end
      end
    end
  end
end
