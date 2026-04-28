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
        pages.each do |page|
          next unless page.html?

          validate_h1(page, issues)
          validate_title(page, issues)
          validate_description(page, issues)
          validate_canonical(page, issues)
          validate_open_graph(page, issues)
        end
      end

      private

      def validate_h1(page, issues)
        h1s = page.doc.css("h1")
        return if h1s.one?

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
        title = page.doc.at_css("title")&.text.to_s.strip

        if title.empty?
          issues.add(code: :missing_title, severity: :warning, category: :metadata, url: page.url, message: "missing <title>", details: {})
        elsif title.length > TITLE_MAX_LENGTH
          issues.add(code: :title_too_long, severity: :warning, category: :metadata, url: page.url, message: "title too long (#{title.length})", details: {length: title.length})
        elsif repeated_site_name?(title)
          issues.add(code: :title_repeats_site_name, severity: :warning, category: :metadata, url: page.url, message: "title repeats #{@site_name}", details: {site_name: @site_name})
        end
      end

      def validate_description(page, issues)
        description = page.doc.at_css('meta[name="description"]')&.[]("content").to_s.strip

        if description.empty?
          issues.add(code: :missing_meta_description, severity: :warning, category: :metadata, url: page.url, message: "missing meta description", details: {})
        elsif description.length < DESCRIPTION_MIN_LENGTH
          issues.add(code: :meta_description_too_short, severity: :warning, category: :metadata, url: page.url, message: "meta description too short (#{description.length})", details: {length: description.length, minimum: DESCRIPTION_MIN_LENGTH})
        elsif description.length > DESCRIPTION_MAX_LENGTH
          issues.add(code: :meta_description_too_long, severity: :warning, category: :metadata, url: page.url, message: "meta description too long (#{description.length})", details: {length: description.length})
        end
      end

      def validate_canonical(page, issues)
        canonical = page.doc.at_css('link[rel="canonical"]')&.[]("href").to_s.strip

        if canonical.empty?
          issues.add(code: :missing_canonical, severity: :warning, category: :metadata, url: page.url, message: "missing canonical link", details: {})
          return
        end

        normalized_canonical = Url.normalize(canonical, base_url: page.url)
        normalized_page_url = Url.normalize(page.url, base_url: page.url)
        return if canonical_matches_page?(normalized_canonical, normalized_page_url)

        issues.add(
          code: :canonical_mismatch,
          severity: :warning,
          category: :metadata,
          url: page.url,
          message: "canonical mismatch (#{canonical})",
          details: {canonical: canonical}
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
