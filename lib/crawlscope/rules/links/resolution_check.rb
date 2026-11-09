# frozen_string_literal: true

module Crawlscope
  module Rules
    class Links
      class ResolutionCheck
        def initialize(targets:, allowed_statuses:, scope:)
          @targets = targets
          @allowed_statuses = allowed_statuses
          @scope = scope
        end

        def call(links, issues:)
          resolved_links = []
          grouped_links_by_target = links.group_by { |link| link[:target_url] }
          @targets.resolve_all(grouped_links_by_target.keys)

          grouped_links_by_target.each do |target_url, grouped_links|
            target = @targets.fetch(target_url)

            if target.unresolved?
              report_unresolved_target(target_url, grouped_links, issues, target.resolution)
              next
            end

            if target.ignored_error?
              next
            end

            unless target.allowed?(@allowed_statuses)
              report_broken_target(target_url, grouped_links, issues, target.status)
              next
            end

            report_redirect_target(target_url, grouped_links, issues, target) if target.redirect?
            next unless @scope.crawlable_path?(target.final_path)

            grouped_links.each do |link|
              resolved_links << link.merge(final_path: target.final_path, final_url: target.final_url)
            end
          end

          resolved_links
        end

        private

        def report_broken_target(target_url, grouped_links, issues, status)
          source_urls = grouped_links.map { |link| link[:source_url] }.uniq
          issues.add(
            code: :broken_internal_link,
            severity: :warning,
            category: :links,
            url: target_url,
            message: "linked URL returns HTTP #{status}",
            details: {source_urls: source_urls, status: status}
          )
        end

        def report_unresolved_target(target_url, grouped_links, issues, resolution)
          source_urls = grouped_links.map { |link| link[:source_url] }.uniq
          suffix = (resolution && resolution[:error]) ? ": #{resolution[:error]}" : ""

          issues.add(
            code: :unresolved_internal_link,
            severity: :warning,
            category: :links,
            url: target_url,
            message: "cannot check linked URL#{suffix}",
            details: {error: resolution && resolution[:error], source_urls: source_urls}
          )
        end

        def report_redirect_target(target_url, grouped_links, issues, target)
          source_urls = grouped_links.map { |link| link[:source_url] }.uniq
          issues.add(
            code: :internal_link_redirects,
            severity: :warning,
            category: :links,
            url: target_url,
            message: "internal link redirects to #{target.final_url}",
            details: {final_url: target.final_url, source_urls: source_urls, status: target.status}
          )
        end
      end
    end
  end
end
