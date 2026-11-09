# frozen_string_literal: true

module Crawlscope
  module Rules
    class Links
      class Extractor
        def initialize(base_url:, concurrency:, fetch_executor:, scope:)
          @base_url = base_url
          @base_host = URI.parse(base_url).host
          @concurrency = concurrency
          @fetch_executor = fetch_executor
          @scope = scope
        end

        def call(pages)
          html_pages = pages.select(&:html?)
          FetchExecutor.map(
            name: @fetch_executor,
            concurrency: @concurrency,
            items: html_pages
          ) { |page| page_links(page) }.flatten
        end

        private

        def page_links(page)
          source_path = Url.path(page.normalized_url)
          return [] unless @scope.crawlable_source_path?(source_path)

          contextual_links(page.doc).filter_map do |node|
            link_for(page: page, source_path: source_path, node: node)
          end
        end

        def contextual_links(doc)
          doc.css(LINK_SELECTORS)
        end

        def link_for(page:, source_path:, node:)
          href = node["href"].to_s.strip
          return unless crawlable_href?(href)

          anchor_text = normalize_anchor_text(node.text)
          return if anchor_text.empty?

          target_url = normalize_internal_link(page.normalized_url, href)
          return if target_url.nil?

          target_path = Url.path(target_url)
          return unless @scope.crawlable_path?(target_path)

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
      end
    end
  end
end
