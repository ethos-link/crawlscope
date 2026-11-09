# frozen_string_literal: true

require "uri"

module Crawlscope
  module Rules
    class Links
      LinkTarget = Crawling::Target

      LINK_SELECTORS = "a[href]"
      INTERNAL_PATH_PREFIXES_TO_SKIP = ["/rails/", "/cdn-cgi/"].freeze
      LINK_SCHEMES_TO_SKIP = ["mailto:", "tel:", "javascript:", "data:"].freeze
      MIN_INBOUND_ANCHOR_LINKS = 1
      MIN_DOFOLLOW_INBOUND_LINKS = 2

      attr_reader :code

      def initialize
        @code = :links
      end

      def call(urls:, pages:, issues:, context:)
        scope = Scope.new
        targets = TargetLookup.new(context: context)
        links = Extractor.new(base_url: context.fetch(:base_url),
          concurrency: context_value(context, :concurrency, default: 1),
          fetch_executor: context_value(context, :fetch_executor), scope: scope).call(pages)
        UrlChecks.new(base_url: context.fetch(:base_url)).call(urls: urls, links: links, issues: issues)
        resolved_links = ResolutionCheck.new(targets: targets,
          allowed_statuses: context.fetch(:allowed_statuses), scope: scope).call(links, issues: issues)
        graph = Graph.new(links: resolved_links, targets: targets)
        OutgoingChecks.new(base_url: context.fetch(:base_url), targets: targets,
          allowed_statuses: context.fetch(:allowed_statuses), scope: scope).call(
            urls: urls, pages: pages, links: links, resolved_links: resolved_links, issues: issues
          )
        InboundChecks.new(base_url: context.fetch(:base_url), graph: graph, scope: scope).call(urls: urls, pages: pages, issues: issues)
        CanonicalChecks.new(base_url: context.fetch(:base_url), targets: targets,
          allowed_statuses: context.fetch(:allowed_statuses), graph: graph).call(urls: urls, pages: pages, issues: issues)
      end

      private

      def context_value(context, name, default: nil)
        if context.respond_to?(name)
          context.public_send(name)
        elsif context.respond_to?(:key?) && context.key?(name)
          context[name]
        else
          default
        end
      end
    end
  end
end
