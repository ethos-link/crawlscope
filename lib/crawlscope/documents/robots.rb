# frozen_string_literal: true

module Crawlscope
  module Documents
    class Robots
      ROBOTS_META_SELECTOR = 'meta[name="robots"], meta[name="googlebot"]'
      X_ROBOTS_TAG_HEADER = "x-robots-tag"

      def self.noindex_header?(headers)
        noindex?(header_value(headers, X_ROBOTS_TAG_HEADER))
      end

      def self.noindex_meta?(doc)
        return false unless doc

        doc.css(ROBOTS_META_SELECTOR).any? { |tag| noindex?(tag["content"].to_s) }
      end

      def self.header_value(headers, name)
        headers.find { |key, _value| key.to_s.casecmp?(name) }&.last.to_s
      end

      def self.directives(value)
        value
          .split(",")
          .map { |directive| directive.split(":", 2).last.to_s.strip }
          .reject(&:empty?)
      end

      def self.noindex?(value)
        new(value).noindex?
      end

      def initialize(value)
        @directives = self.class.directives(value)
      end

      def noindex?
        include?("noindex") || include?("none")
      end

      def nofollow?
        include?("nofollow") || include?("none")
      end

      def follow?
        include?("follow")
      end

      private

      def include?(value)
        @directives.any? { |directive| directive.casecmp?(value) }
      end
    end
  end
end
