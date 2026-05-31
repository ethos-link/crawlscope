# frozen_string_literal: true

require "uri"

module Crawlscope
  module Rules
    class Metadata
      TITLE_MAX_LENGTH = 72
      DESCRIPTION_MIN_LENGTH = 110
      DESCRIPTION_MAX_LENGTH = 160
      REQUIRED_OPEN_GRAPH_PROPERTIES = %w[og:title og:description og:url og:type og:image].freeze

      attr_reader :code

      def initialize(site_name: nil)
        @site_name = site_name.to_s.strip
        @code = :metadata
      end

      def call(urls:, pages:, issues:, context: nil)
        sitemap_urls = normalized_sitemap_urls(urls)

        pages.each do |page|
          next unless page.html?

          validate_h1(page, issues)
          validate_title(page, issues)
          validate_description(page, issues)
          validate_canonical(page, issues, sitemap_urls)
          validate_open_graph(page, issues)
        end
      end

      private

      def normalized_sitemap_urls(urls)
        urls.map { |url| Url.normalize(url, base_url: url) }.compact
      end

      def validate_h1(page, issues)
        h1s = page.doc.css("h1")
        empty_h1s = h1s.select { |node| node.text.to_s.strip.empty? }

        if empty_h1s.any?
          issues.add(
            code: :empty_h1,
            severity: :warning,
            category: :metadata,
            url: page.url,
            message: "empty <h1>",
            details: {count: empty_h1s.size}
          )
        end

        return if h1s.one? && empty_h1s.empty?

        if h1s.empty?
          issues.add(
            code: :missing_h1,
            severity: :warning,
            category: :metadata,
            url: page.url,
            message: "missing <h1>",
            details: {}
          )
        else
          issues.add(
            code: :multiple_h1,
            severity: :warning,
            category: :metadata,
            url: page.url,
            message: "multiple <h1> tags (#{h1s.size})",
            details: {count: h1s.size}
          )
        end
      end

      def validate_title(page, issues)
        titles = page.doc.css("head > title")
        title = titles.first&.text.to_s.strip

        if titles.size > 1
          issues.add(
            code: :multiple_title_tags,
            severity: :warning,
            category: :metadata,
            url: page.url,
            message: "multiple <title> tags (#{titles.size})",
            details: {count: titles.size}
          )
        end

        if title.empty?
          issues.add(code: :missing_title, severity: :warning, category: :metadata, url: page.url, message: "missing <title>", details: {})
        elsif title.length > TITLE_MAX_LENGTH
          issues.add(code: :title_too_long, severity: :warning, category: :metadata, url: page.url, message: "title too long (#{title.length})", details: {length: title.length})
        elsif repeated_site_name?(title)
          issues.add(code: :title_repeats_site_name, severity: :warning, category: :metadata, url: page.url, message: "title repeats #{@site_name}", details: {site_name: @site_name})
        end
      end

      def validate_description(page, issues)
        descriptions = page.doc.css('head > meta[name="description"]')
        description = descriptions.first&.[]("content").to_s.strip

        if descriptions.size > 1
          issues.add(
            code: :multiple_meta_descriptions,
            severity: :warning,
            category: :metadata,
            url: page.url,
            message: "multiple meta description tags (#{descriptions.size})",
            details: {count: descriptions.size}
          )
        end

        if description.empty?
          issues.add(code: :missing_meta_description, severity: :warning, category: :metadata, url: page.url, message: "missing meta description", details: {})
        elsif description.length < DESCRIPTION_MIN_LENGTH
          issues.add(code: :meta_description_too_short, severity: :warning, category: :metadata, url: page.url, message: "meta description too short (#{description.length})", details: {length: description.length, minimum: DESCRIPTION_MIN_LENGTH})
        elsif description.length > DESCRIPTION_MAX_LENGTH
          issues.add(code: :meta_description_too_long, severity: :warning, category: :metadata, url: page.url, message: "meta description too long (#{description.length})", details: {length: description.length})
        end
      end

      def validate_canonical(page, issues, sitemap_urls)
        canonical = page.doc.at_css('link[rel="canonical"]')&.[]("href").to_s.strip

        if canonical.empty?
          issues.add(code: :missing_canonical, severity: :warning, category: :metadata, url: page.url, message: "missing canonical link", details: {})
          return
        end

        normalized_canonical = Url.normalize(canonical, base_url: page.url)
        normalized_page_url = Url.normalize(page.url, base_url: page.url)
        return if canonical_matches_page?(normalized_canonical, normalized_page_url)

        details = {canonical: canonical}
        issues.add(
          code: :canonical_mismatch,
          severity: :warning,
          category: :metadata,
          url: page.url,
          message: "canonical mismatch (#{canonical})",
          details: details
        )

        return unless sitemap_urls.include?(normalized_page_url)

        issues.add(
          code: :non_canonical_page_in_sitemap,
          severity: :warning,
          category: :sitemaps,
          url: page.url,
          message: "non-canonical page is included in sitemap",
          details: details
        )
      end

      def repeated_site_name?(title)
        return false if @site_name.empty?

        title.split(/[^[:alnum:]]+/).count { |token| token.casecmp?(@site_name) } > 1
      end

      def validate_open_graph(page, issues)
        missing = REQUIRED_OPEN_GRAPH_PROPERTIES.reject do |property|
          page.doc.at_css(%(meta[property="#{property}"][content]))
        end
        return if missing.empty?

        issues.add(
          code: :incomplete_open_graph_tags,
          severity: :warning,
          category: :metadata,
          url: page.url,
          message: "Open Graph tags incomplete (missing #{missing.join(", ")})",
          details: {missing: missing}
        )
      end

      def canonical_matches_page?(canonical, page_url)
        canonical == page_url || (local_url?(page_url) && Url.path(canonical) == Url.path(page_url))
      end

      def local_url?(url)
        host = URI.parse(url.to_s).host.to_s
        ["localhost", "127.0.0.1", "0.0.0.0", "::1"].include?(host)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
