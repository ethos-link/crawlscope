# frozen_string_literal: true

module Crawlscope
  module Crawling
    class TargetResolver
      def initialize(base_url:, crawler:, pages:)
        @base_url = base_url
        @crawler = crawler
        @pages = {}
        @targets = {}

        pages.each do |page|
          cache_page(page)
        end
      end

      def call(target_urls)
        normalized_by_url = Array(target_urls).to_h do |target_url|
          [target_url, Url.normalize(target_url, base_url: @base_url)]
        end
        normalized_urls = normalized_by_url.values.compact.uniq
        missing_urls = []

        normalized_urls.each do |normalized_url|
          next if @targets.key?(normalized_url)

          resolved = resolved_page(normalized_url)
          if resolved
            @targets[normalized_url] = resolved
          else
            missing_urls << normalized_url
          end
        end

        fetched_pages(missing_urls).each do |page|
          normalized_url = Url.normalize(page.url, base_url: @base_url)
          cache_page(page)
          @targets[normalized_url] = resolution(page, normalized_url, crawled: false)
        end

        normalized_by_url.to_h { |target_url, normalized_url| [target_url, @targets[normalized_url]] }
      end

      private

      def cache_page(page)
        @pages[page.normalized_url] = page unless page.normalized_url.to_s.empty?
        @pages[page.normalized_final_url] = page unless page.normalized_final_url.to_s.empty?
      end

      def fetched_pages(normalized_urls)
        return [] if normalized_urls.empty?

        @crawler.call(normalized_urls)
      end

      def resolved_page(normalized_url)
        page = @pages[normalized_url]
        resolution(page, normalized_url, crawled: true) if page
      end

      def resolution(page, normalized_url, crawled:)
        {
          crawled: crawled,
          doc: page.doc,
          error: page.error,
          final_url: page.normalized_final_url || normalized_url,
          headers: page.headers,
          html: page.html?,
          status: page.status
        }
      end
    end
  end
end
