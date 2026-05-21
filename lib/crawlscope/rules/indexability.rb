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
        pages.each do |page|
          next unless page.html?

          validate_meta_robots(page, issues)
          validate_x_robots_tag(page, issues)
        end
      end

      private

      def header_value(page, name)
        page.headers.find { |key, _value| key.to_s.casecmp?(name) }&.last.to_s
      end

      def noindex?(value)
        value.split(",").map(&:strip).any? { |directive| directive.casecmp?("noindex") }
      end

      def validate_meta_robots(page, issues)
        page.doc.css(ROBOTS_META_SELECTOR).each do |tag|
          content = tag["content"].to_s
          next unless noindex?(content)

          issues.add(
            code: :noindex_meta,
            severity: :error,
            category: :indexability,
            url: page.url,
            message: "robots meta tag prevents indexing",
            details: {content: content, name: tag["name"].to_s}
          )
        end
      end

      def validate_x_robots_tag(page, issues)
        content = header_value(page, X_ROBOTS_TAG_HEADER)
        return unless noindex?(content)

        issues.add(
          code: :noindex_header,
          severity: :error,
          category: :indexability,
          url: page.url,
          message: "X-Robots-Tag header prevents indexing",
          details: {content: content}
        )
      end
    end
  end
end
