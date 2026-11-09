# frozen_string_literal: true

module Crawlscope
  module Documents
    class Canonical
      attr_reader :href

      def initialize(doc:, base_url:)
        @href = doc&.at_css('link[rel="canonical"]')&.[]("href").to_s.strip
        @base_url = base_url
      end

      def present?
        !href.empty?
      end

      def url
        Url.normalize(href, base_url: @base_url) if present?
      end
    end
  end
end
