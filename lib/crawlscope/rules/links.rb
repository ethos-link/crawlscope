# frozen_string_literal: true

require "uri"

module Crawlscope
  module Rules
    class Links
      LINK_SELECTORS = "a[href]"
      INTERNAL_PATH_PREFIXES_TO_SKIP = ["/rails/", "/cdn-cgi/"].freeze
      LINK_SCHEMES_TO_SKIP = ["mailto:", "tel:", "javascript:", "data:"].freeze
      MAX_SOURCES_IN_ERROR = 3
      MIN_INBOUND_ANCHOR_LINKS = 1
      MIN_DOFOLLOW_INBOUND_LINKS = 2

      attr_reader :code

      def initialize
        @code = :links
      end

      def call(urls:, pages:, issues:, context:)
        @allowed_statuses = context.fetch(:allowed_statuses)
        @base_url = context.fetch(:base_url)
        @resolve_target = context.fetch(:resolve_target)
        @base_host = URI.parse(@base_url).host

        links = extract_links(pages)
        validate_url_hygiene(urls, links, issues)
        resolved_links = resolve_links(links, issues)
        validate_nofollow_outgoing_links(links, issues)
        validate_http_internal_links(links, issues)
        validate_pages_with_no_outgoing_links(urls, pages, links, issues)
        validate_indexable_pages_missing_from_sitemap(urls, resolved_links, issues)
        validate_inbound_counts(urls, pages, resolved_links, issues)
        validate_canonical_targets(urls, pages, resolved_links, issues)
      end

      private

      def contextual_links(doc)
        doc.css(LINK_SELECTORS)
      end

      def extract_links(pages)
        pages.select(&:html?).flat_map { |page| page_links(page) }
      end

      def page_links(page)
        source_path = Url.path(page.normalized_url)
        return [] unless crawlable_source_path?(source_path)

        contextual_links(page.doc).filter_map do |node|
          link_for(page: page, source_path: source_path, node: node)
        end
      end

      def link_for(page:, source_path:, node:)
        href = node["href"].to_s.strip
        return unless crawlable_href?(href)

        anchor_text = normalize_anchor_text(node.text)
        return if anchor_text.empty?

        target_url = normalize_internal_link(page.normalized_url, href)
        return if target_url.nil?

        target_path = Url.path(target_url)
        return unless crawlable_path?(target_path)

        {
          anchor_text: anchor_text,
          http_internal_link: http_internal_link?(page.normalized_url, href),
          nofollow: nofollow_link?(node),
          source_path: source_path,
          source_url: page.normalized_url,
          target_path: target_path,
          target_url: target_url
        }
      end

      def crawlable_href?(href)
        return false if href.empty?
        return false if href.start_with?("#")

        LINK_SCHEMES_TO_SKIP.none? { |prefix| href.start_with?(prefix) }
      end

      def crawlable_path?(path)
        !path.nil? && !skip_internal_path?(path)
      end

      def normalize_anchor_text(text)
        text.to_s.gsub(/\s+/, " ").strip
      end

      def nofollow_link?(node)
        node["rel"].to_s.split(/\s+/).any? { |value| value.casecmp?("nofollow") }
      end

      def http_internal_link?(source_url, href)
        source_uri = URI.parse(source_url.to_s)
        target_uri = URI.parse(URI.join(source_url, href).to_s)

        source_uri.scheme == "https" && target_uri.scheme == "http" && target_uri.host == @base_host
      rescue URI::InvalidURIError
        false
      end

      def normalize_internal_link(source_url, href)
        absolute_url = URI.join(source_url, href).to_s
        uri = URI.parse(absolute_url)
        return if uri.host != @base_host

        uri.fragment = nil
        Url.normalize(uri.to_s, base_url: @base_url)
      rescue URI::InvalidURIError
        nil
      end

      def report_broken_target(target_url, grouped_links, issues, status)
        source_urls = grouped_links.map { |link| link[:source_url] }.uniq.first(MAX_SOURCES_IN_ERROR)
        issues.add(
          code: :broken_internal_link,
          severity: :warning,
          category: :links,
          url: target_url,
          message: "broken internal link (HTTP #{status}, sources: #{source_urls.join(", ")})",
          details: {source_urls: source_urls, status: status}
        )
      end

      def validate_nofollow_outgoing_links(links, issues)
        links.select { |link| link[:nofollow] }.group_by { |link| link[:source_url] }.each do |source_url, grouped_links|
          target_urls = grouped_links.map { |link| link[:target_url] }.uniq.first(MAX_SOURCES_IN_ERROR)

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
          target_urls = grouped_links.map { |link| link[:target_url] }.uniq.first(MAX_SOURCES_IN_ERROR)

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

      def report_unresolved_target(target_url, grouped_links, issues, resolution)
        source_urls = grouped_links.map { |link| link[:source_url] }.uniq.first(MAX_SOURCES_IN_ERROR)
        suffix = (resolution && resolution[:error]) ? " (#{resolution[:error]})" : ""

        issues.add(
          code: :unresolved_internal_link,
          severity: :warning,
          category: :links,
          url: target_url,
          message: "unable to validate internal link#{suffix} (sources: #{source_urls.join(", ")})",
          details: {error: resolution && resolution[:error], source_urls: source_urls}
        )
      end

      def resolve_links(links, issues)
        resolved_links = []

        links.group_by { |link| link[:target_url] }.each do |target_url, grouped_links|
          target = resolve_target(target_url)

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
          next unless crawlable_path?(target.final_path)

          grouped_links.each do |link|
            resolved_links << link.merge(final_path: target.final_path, final_url: target.final_url)
          end
        end

        resolved_links
      end

      def report_redirect_target(target_url, grouped_links, issues, target)
        source_urls = grouped_links.map { |link| link[:source_url] }.uniq.first(MAX_SOURCES_IN_ERROR)
        issues.add(
          code: :internal_link_redirects,
          severity: :warning,
          category: :links,
          url: target_url,
          message: "internal link redirects to #{target.final_url} (sources: #{source_urls.join(", ")})",
          details: {final_url: target.final_url, source_urls: source_urls, status: target.status}
        )
      end

      def resolve_target(target_url)
        resolution = @resolve_target.call(target_url)
        LinkTarget.new(target_url: target_url, resolution: resolution)
      end

      LinkTarget = Data.define(:target_url, :resolution) do
        def allowed?(statuses)
          statuses.include?(status)
        end

        def final_path
          Url.path(final_url)
        end

        def final_url
          value = resolution[:final_url].to_s
          value.empty? ? target_url : value
        end

        def ignored_error?
          resolution && status.nil? && resolution[:crawled] && resolution[:error]
        end

        def html?
          resolution && resolution[:html]
        end

        def noindex?
          Crawlscope::Rules::Indexability.noindex_header?(resolution[:headers] || {}) ||
            Crawlscope::Rules::Indexability.noindex_meta?(resolution[:doc])
        end

        def status
          resolution && resolution[:status]
        end

        def redirect?
          (status && (300..399).cover?(status.to_i)) || final_url != target_url
        end

        def unresolved?
          resolution.nil? || (status.nil? && !ignored_error?)
        end
      end

      def crawlable_source_path?(path)
        !path.nil? && INTERNAL_PATH_PREFIXES_TO_SKIP.none? { |prefix| path.start_with?(prefix) }
      end

      def skip_internal_path?(path)
        return true if path == "/"

        INTERNAL_PATH_PREFIXES_TO_SKIP.any? { |prefix| path.start_with?(prefix) }
      end

      def validate_inbound_counts(urls, pages, resolved_links, issues)
        sitemap_paths = urls.each_with_object({}) do |url, memo|
          normalized_url = Url.normalize(url, base_url: @base_url)
          path = Url.path(normalized_url)
          next if path.nil?
          next if skip_internal_path?(path)

          memo[path] = normalized_url
        end
        return if sitemap_paths.size < 2

        html_paths = pages.each_with_object(Set.new) do |page, result|
          next unless page.html?

          [page.normalized_url, page.normalized_final_url].compact.each do |url|
            path = Url.path(url)
            next if path.nil?
            next if skip_internal_path?(path)

            result << path
          end
        end

        inbound_anchor_counts = Hash.new(0)
        dofollow_inbound_counts = Hash.new(0)
        nofollow_inbound_counts = Hash.new(0)
        sample_sources_by_target = Hash.new { |hash, key| hash[key] = [] }
        dofollow_sources_by_target = Hash.new { |hash, key| hash[key] = [] }
        nofollow_sources_by_target = Hash.new { |hash, key| hash[key] = [] }

        resolved_links.each do |link|
          target_path = link[:final_path]
          next unless sitemap_paths.key?(target_path)
          next if link[:source_path] == target_path

          inbound_anchor_counts[target_path] += 1
          source_samples = sample_sources_by_target[target_path]
          source_samples << link[:source_url] unless source_samples.include?(link[:source_url])

          if link[:nofollow]
            nofollow_inbound_counts[target_path] += 1
            nofollow_sources = nofollow_sources_by_target[target_path]
            nofollow_sources << link[:source_url] unless nofollow_sources.include?(link[:source_url])
          else
            dofollow_inbound_counts[target_path] += 1
            dofollow_sources = dofollow_sources_by_target[target_path]
            dofollow_sources << link[:source_url] unless dofollow_sources.include?(link[:source_url])
          end
        end

        sitemap_paths.each do |path, target_url|
          next unless html_paths.include?(path)

          inbound_count = inbound_anchor_counts[path]
          dofollow_count = dofollow_inbound_counts[path]
          nofollow_count = nofollow_inbound_counts[path]

          report_orphan_page(target_url, issues) if inbound_count.zero?

          if inbound_count.positive? && inbound_count < MIN_INBOUND_ANCHOR_LINKS
            source_samples = sample_sources_by_target[path].first(MAX_SOURCES_IN_ERROR)
            source_info = source_samples.any? ? " (sources: #{source_samples.join(", ")})" : ""

            issues.add(
              code: :low_inbound_anchor_links,
              severity: :warning,
              category: :links,
              url: target_url,
              message: "inbound anchor links #{inbound_count} below #{MIN_INBOUND_ANCHOR_LINKS}#{source_info}",
              details: {inbound_count: inbound_count, minimum: MIN_INBOUND_ANCHOR_LINKS, source_urls: source_samples}
            )
          end

          report_low_dofollow_inlinks(target_url, path, dofollow_count, dofollow_sources_by_target, issues)
          report_only_nofollow_internal_inlinks(target_url, nofollow_count, dofollow_count, nofollow_sources_by_target[path], issues)
          report_mixed_follow_internal_inlinks(target_url, nofollow_count, dofollow_count, nofollow_sources_by_target[path], dofollow_sources_by_target[path], issues)
        end
      end

      def validate_url_hygiene(urls, links, issues)
        checked_urls = urls.map { |url| Url.normalize(url, base_url: @base_url) }
        checked_urls.concat(links.map { |link| link[:target_url] })

        checked_urls.compact.uniq.each do |url|
          report_url_double_slash(url, issues)
          report_url_too_long(url, issues)
        end
      end

      def report_url_double_slash(url, issues)
        path = URI.parse(url).path.to_s
        return unless path.match?(%r{//+})

        issues.add(
          code: :url_double_slash,
          severity: :notice,
          category: :url,
          url: url,
          message: "URL path contains duplicate slashes",
          details: {path: path}
        )
      rescue URI::InvalidURIError
        nil
      end

      def report_url_too_long(url, issues)
        return unless url.length > 2_048

        issues.add(
          code: :url_too_long,
          severity: :notice,
          category: :url,
          url: url,
          message: "URL too long (#{url.length})",
          details: {length: url.length, maximum: 2_048}
        )
      end

      def validate_pages_with_no_outgoing_links(urls, pages, links, issues)
        sitemap_urls = urls.map { |url| Url.normalize(url, base_url: @base_url) }.compact.to_set
        return if sitemap_urls.size < 2

        source_paths_with_links = links.map { |link| link[:source_path] }.to_set

        pages.each do |page|
          next unless page.html?
          next unless sitemap_urls.include?(page.normalized_url)

          source_path = Url.path(page.normalized_url)
          next unless crawlable_source_path?(source_path)
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
        reported_urls = Set.new

        resolved_links.each do |link|
          final_url = link[:final_url]
          next if sitemap_urls.include?(final_url)
          next if reported_urls.include?(final_url)
          next unless crawlable_path?(link[:final_path])

          target = resolve_target(final_url)
          next unless target.allowed?(@allowed_statuses) && target.html?
          next if target.noindex?

          reported_urls << final_url

          issues.add(
            code: :indexable_page_missing_from_sitemap,
            severity: :warning,
            category: :sitemaps,
            url: final_url,
            message: "indexable internal page is missing from sitemap",
            details: {source_url: link[:source_url]}
          )
        end
      end

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

      def report_low_dofollow_inlinks(target_url, path, dofollow_count, sources_by_target, issues)
        return if dofollow_count.zero?
        return if dofollow_count >= MIN_DOFOLLOW_INBOUND_LINKS

        source_samples = sources_by_target[path].first(MAX_SOURCES_IN_ERROR)
        source_info = source_samples.any? ? " (sources: #{source_samples.join(", ")})" : ""

        issues.add(
          code: :low_dofollow_inlinks,
          severity: :warning,
          category: :links,
          url: target_url,
          message: "dofollow inbound links #{dofollow_count} below #{MIN_DOFOLLOW_INBOUND_LINKS}#{source_info}",
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
          message: "page has nofollow incoming internal links only",
          details: {nofollow_inbound_count: nofollow_count, source_urls: nofollow_sources.first(MAX_SOURCES_IN_ERROR)}
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
            dofollow_source_urls: dofollow_sources.first(MAX_SOURCES_IN_ERROR),
            nofollow_source_urls: nofollow_sources.first(MAX_SOURCES_IN_ERROR)
          }
        )
      end

      def validate_canonical_targets(urls, pages, resolved_links, issues)
        sitemap_urls = urls.map { |url| Url.normalize(url, base_url: @base_url) }.compact
        sitemap_pages = pages.select { |page| page.html? && sitemap_urls.include?(page.normalized_url) }
        return if sitemap_pages.size < 2

        dofollow_counts_by_path = dofollow_counts_by_final_path(resolved_links)

        sitemap_pages.each do |page|
          canonical_url = canonical_url_for(page)
          next if canonical_url.nil?

          target_uri = URI.parse(canonical_url)
          next if target_uri.host != @base_host

          canonical_path = Url.path(canonical_url)
          if canonical_path && dofollow_counts_by_path[canonical_path].zero?
            issues.add(
              code: :canonical_no_internal_inlinks,
              severity: :warning,
              category: :links,
              url: canonical_url,
              message: "canonical URL has no incoming internal links",
              details: {source_url: page.url}
            )
          end

          validate_canonical_target_status(page, canonical_url, issues)
        rescue URI::InvalidURIError
          next
        end
      end

      def dofollow_counts_by_final_path(resolved_links)
        resolved_links.each_with_object(Hash.new(0)) do |link, counts|
          next if link[:nofollow]
          next if link[:source_path] == link[:final_path]

          counts[link[:final_path]] += 1
        end
      end

      def canonical_url_for(page)
        canonical = page.doc.at_css('link[rel="canonical"]')&.[]("href").to_s.strip
        return if canonical.empty?

        Url.normalize(canonical, base_url: page.url)
      end

      def validate_canonical_target_status(page, canonical_url, issues)
        target = resolve_target(canonical_url)

        if target.unresolved? || target.ignored_error?
          return
        end

        if target.redirect?
          issues.add(
            code: :canonical_points_to_redirect,
            severity: :warning,
            category: :metadata,
            url: page.url,
            message: "canonical points to redirect",
            details: {canonical: canonical_url, final_url: target.final_url, status: target.status}
          )
        elsif !target.allowed?(@allowed_statuses)
          issues.add(
            code: :canonical_points_to_error,
            severity: :warning,
            category: :metadata,
            url: page.url,
            message: "canonical points to HTTP #{target.status}",
            details: {canonical: canonical_url, status: target.status}
          )
        end
      end
    end
  end
end
