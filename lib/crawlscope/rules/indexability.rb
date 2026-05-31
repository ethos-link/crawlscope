# frozen_string_literal: true

module Crawlscope
  module Rules
    class Indexability
      ROBOTS_META_SELECTOR = 'meta[name="robots"], meta[name="googlebot"]'
      X_ROBOTS_TAG_HEADER = "x-robots-tag"

      attr_reader :code

      def initialize
        @code = :indexability
      end

      def call(urls:, pages:, issues:, context: nil)
        sitemap_urls = normalized_sitemap_urls(urls)

        pages.each do |page|
          validate_meta_robots(page, issues, sitemap_urls) if page.html?
          validate_x_robots_tag(page, issues, sitemap_urls)
        end
      end

      private

      def normalized_sitemap_urls(urls)
        urls.map { |url| Url.normalize(url, base_url: url) }.compact
      end

      def header_value(page, name)
        page.headers.find { |key, _value| key.to_s.casecmp?(name) }&.last.to_s
      end

      def directives(value)
        value
          .split(",")
          .map { |directive| directive.split(":", 2).last.to_s.strip }
          .reject(&:empty?)
      end

      def noindex?(value)
        directives(value).any? { |directive| directive.casecmp?("noindex") || directive.casecmp?("none") }
      end

      def follow?(value)
        directives(value).any? { |directive| directive.casecmp?("follow") }
      end

      def nofollow?(value)
        directives(value).any? { |directive| directive.casecmp?("nofollow") || directive.casecmp?("none") }
      end

      def validate_meta_robots(page, issues, sitemap_urls)
        page.doc.css(ROBOTS_META_SELECTOR).each do |tag|
          content = tag["content"].to_s

          report_noindex_meta(page, issues, content, tag["name"].to_s, sitemap_urls) if noindex?(content)
          report_nofollow_meta(page, issues, content, tag["name"].to_s) if nofollow?(content)
          report_noindex_follow_meta(page, issues, content, tag["name"].to_s) if noindex?(content) && follow?(content)
          report_noindex_nofollow_meta(page, issues, content, tag["name"].to_s) if noindex?(content) && nofollow?(content)
        end
      end

      def validate_x_robots_tag(page, issues, sitemap_urls)
        content = header_value(page, X_ROBOTS_TAG_HEADER)
        return if content.empty?

        report_noindex_header(page, issues, content, sitemap_urls) if noindex?(content)
        report_nofollow_header(page, issues, content) if nofollow?(content)
        report_noindex_follow_header(page, issues, content) if noindex?(content) && follow?(content)
        report_noindex_nofollow_header(page, issues, content) if noindex?(content) && nofollow?(content)
      end

      def report_noindex_meta(page, issues, content, name, sitemap_urls)
        issues.add(
          code: :noindex_meta,
          severity: :error,
          category: :indexability,
          url: page.url,
          message: "robots meta tag prevents indexing",
          details: {content: content, name: name}
        )
        report_sitemap_noindex_url(page, issues, content, source: "meta", sitemap_urls: sitemap_urls)
      end

      def report_nofollow_meta(page, issues, content, name)
        issues.add(
          code: :nofollow_meta,
          severity: :warning,
          category: :indexability,
          url: page.url,
          message: "robots meta tag prevents following links",
          details: {content: content, name: name}
        )
      end

      def report_noindex_follow_meta(page, issues, content, name)
        issues.add(
          code: :noindex_follow_meta,
          severity: :warning,
          category: :indexability,
          url: page.url,
          message: "robots meta tag prevents indexing but allows following links",
          details: {content: content, name: name}
        )
      end

      def report_noindex_nofollow_meta(page, issues, content, name)
        issues.add(
          code: :noindex_nofollow_meta,
          severity: :error,
          category: :indexability,
          url: page.url,
          message: "robots meta tag prevents indexing and following links",
          details: {content: content, name: name}
        )
      end

      def report_noindex_header(page, issues, content, sitemap_urls)
        issues.add(
          code: :noindex_header,
          severity: :error,
          category: :indexability,
          url: page.url,
          message: "X-Robots-Tag header prevents indexing",
          details: {content: content}
        )
        report_sitemap_noindex_url(page, issues, content, source: "header", sitemap_urls: sitemap_urls)
      end

      def report_nofollow_header(page, issues, content)
        issues.add(
          code: :nofollow_header,
          severity: :warning,
          category: :indexability,
          url: page.url,
          message: "X-Robots-Tag header prevents following links",
          details: {content: content}
        )
      end

      def report_noindex_follow_header(page, issues, content)
        issues.add(
          code: :noindex_follow_header,
          severity: :warning,
          category: :indexability,
          url: page.url,
          message: "X-Robots-Tag header prevents indexing but allows following links",
          details: {content: content}
        )
      end

      def report_noindex_nofollow_header(page, issues, content)
        issues.add(
          code: :noindex_nofollow_header,
          severity: :error,
          category: :indexability,
          url: page.url,
          message: "X-Robots-Tag header prevents indexing and following links",
          details: {content: content}
        )
      end

      def report_sitemap_noindex_url(page, issues, content, source:, sitemap_urls:)
        normalized_url = Url.normalize(page.url, base_url: page.url)
        return unless sitemap_urls.include?(normalized_url)

        issues.add(
          code: :sitemap_noindex_url,
          severity: :error,
          category: :sitemaps,
          url: page.url,
          message: "sitemap URL is noindex",
          details: {content: content, source: source}
        )
      end
    end
  end
end
