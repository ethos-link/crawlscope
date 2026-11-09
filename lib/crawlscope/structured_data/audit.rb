# frozen_string_literal: true

module Crawlscope
  module StructuredData
    class Audit
      Page = Entry
      Outcome = Crawlscope::StructuredData::Outcome

      def initialize(schema_registry:, renderer:, timeout_seconds:, browser_factory: nil, network_idle_timeout_seconds: Configuration::DEFAULT_BROWSER_NETWORK_IDLE_TIMEOUT_SECONDS, scroll_page: Configuration::DEFAULT_BROWSER_SCROLL_PAGE)
        @schema_registry = schema_registry
        @renderer = renderer.to_sym
        @timeout_seconds = timeout_seconds
        @browser_factory = browser_factory
        @network_idle_timeout_seconds = network_idle_timeout_seconds
        @scroll_page = scroll_page
      end

      def call(urls:)
        fetcher = build_fetcher(urls)
        entries = urls.map { |url| validate_url(url, fetcher) }

        Outcome.new(entries: entries)
      ensure
        fetcher&.close
      end

      private

      def build_fetcher(urls)
        Crawling::FetcherFactory.new(
          base_url: urls.first || "http://localhost:3000", renderer: @renderer,
          timeout_seconds: @timeout_seconds, browser_factory: @browser_factory,
          network_idle_timeout_seconds: @network_idle_timeout_seconds,
          scroll_page: @scroll_page
        ).call
      end

      def build_validation_errors(page)
        validation = Validator.new(schema_registry: @schema_registry).call(html: page.body)
        structured_items = validation.items.map { |item| {data: item.data, source: item.source} }
        errors = validation.findings.map do |finding|
          {errors: finding.errors, source: finding.source, type: finding.type}
        end
        [structured_items, errors]
      end

      def validate_url(url, fetcher)
        page = fetcher.fetch(url)
        content_type = page.header("content-type").to_s

        if page.error
          Page.new(url: url, status: page.status, structured_items: [], errors: [], fetch_error: page.error, content_type: content_type, skipped_reason: nil)
        elsif page.status && !(200..299).cover?(page.status.to_i)
          Page.new(
            url: url,
            status: page.status,
            structured_items: [],
            errors: [],
            fetch_error: "Non-success status",
            content_type: content_type,
            skipped_reason: nil
          )
        elsif !content_type.empty? && !content_type.include?("text/html")
          Page.new(
            url: url,
            status: page.status,
            structured_items: [],
            errors: [],
            fetch_error: nil,
            content_type: content_type,
            skipped_reason: "non-html"
          )
        else
          structured_items, errors = build_validation_errors(page)
          Page.new(
            url: url,
            status: page.status,
            structured_items: structured_items,
            errors: errors,
            fetch_error: nil,
            content_type: content_type,
            skipped_reason: nil
          )
        end
      end
    end
  end
end
