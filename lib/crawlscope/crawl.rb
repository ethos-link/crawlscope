# frozen_string_literal: true

module Crawlscope
  class Crawl
    def initialize(base_url:, sitemap_path:, rules:, schema_registry:, browser_factory: nil, concurrency: Configuration::DEFAULT_CONCURRENCY, fetch_executor: nil, network_idle_timeout_seconds: Configuration::DEFAULT_BROWSER_NETWORK_IDLE_TIMEOUT_SECONDS, profile_token: nil, renderer: :http, scroll_page: Configuration::DEFAULT_BROWSER_SCROLL_PAGE, timeout_seconds: Configuration::DEFAULT_TIMEOUT_SECONDS, allowed_statuses: Configuration::DEFAULT_ALLOWED_STATUSES)
      @base_url = base_url
      @sitemap_path = sitemap_path
      @rules = Array(rules)
      @schema_registry = schema_registry
      @browser_factory = browser_factory
      @concurrency = concurrency
      @network_idle_timeout_seconds = network_idle_timeout_seconds
      @profile_token = profile_token
      @renderer = renderer.to_sym
      @fetch_executor = fetch_executor || default_fetch_executor
      @scroll_page = scroll_page
      @timeout_seconds = timeout_seconds
      @allowed_statuses = allowed_statuses
    end

    def call
      validate_fetch_executor!

      urls = sitemap_urls

      @page_fetcher = page
      pages = Crawler.new(page_fetcher: @page_fetcher, concurrency: @concurrency, fetch_executor: @fetch_executor).call(urls)
      issues = IssueCollection.new

      collect(pages, issues)
      @target_resolver = Crawling::TargetResolver.new(
        base_url: @base_url, pages: pages,
        crawler: Crawler.new(page_fetcher: @page_fetcher, concurrency: @concurrency, fetch_executor: @fetch_executor)
      )
      scan(urls, pages, issues)

      Result.new(
        base_url: @base_url,
        sitemap_path: @sitemap_path,
        urls: urls,
        pages: pages,
        issues: issues
      )
    ensure
      @page_fetcher&.close
    end

    private

    def sitemap_urls
      urls = Sitemap.new(
        path: @sitemap_path,
        adapter: http_adapter,
        concurrency: @concurrency,
        fetch_executor: @fetch_executor,
        profile_token: @profile_token,
        timeout_seconds: @timeout_seconds
      ).urls(base_url: @base_url)
      raise ValidationError, "No URLs found in sitemap: #{@sitemap_path}" if urls.empty?

      urls
    end

    def page
      Crawling::FetcherFactory.new(
        base_url: @base_url, renderer: @renderer, timeout_seconds: @timeout_seconds,
        browser_factory: @browser_factory, profile_token: @profile_token,
        network_idle_timeout_seconds: @network_idle_timeout_seconds,
        scroll_page: @scroll_page, adapter: http_adapter
      ).call
    end

    def http_adapter
      return unless FetchExecutor.normalize(@fetch_executor) == :async

      require "async/http/faraday"
      :async_http
    end

    def validate_fetch_executor!
      return unless @renderer == :browser && FetchExecutor.normalize(@fetch_executor) == :async

      raise ConfigurationError, "Async fetch execution is only supported with http rendering"
    end

    def default_fetch_executor
      (@renderer == :browser) ? :threaded : Configuration::DEFAULT_FETCH_EXECUTOR
    end

    def context
      Context.new(
        allowed_statuses: @allowed_statuses,
        base_url: @base_url,
        concurrency: @concurrency,
        fetch_executor: @fetch_executor,
        resolve_target: method(:resolve),
        resolve_targets: method(:resolve_all),
        schema_registry: @schema_registry
      )
    end

    def collect(pages, issues)
      pages.each do |page|
        if page.error
          issues.add(code: :fetch_failed, severity: :error, category: :crawl, url: page.url, message: page.error, details: {})
        elsif !@allowed_statuses.include?(page.status)
          issues.add(code: :unexpected_status, severity: :error, category: :crawl, url: page.url, message: "HTTP #{page.status}", details: {status: page.status})
        elsif redirected?(page)
          issues.add(code: :sitemap_redirect_url, severity: :warning, category: :sitemaps, url: page.url, message: "sitemap URL redirects to #{page.final_url}", details: {final_url: page.final_url, status: page.status})
        end
      end
    end

    def scan(urls, pages, issues)
      @rules.each do |rule|
        rule.call(urls: urls, pages: pages, issues: issues, context: context)
      end
    end

    def resolve(target_url)
      resolve_all([target_url]).fetch(target_url)
    end

    def resolve_all(target_urls)
      @target_resolver.call(target_urls)
    end

    def redirected?(page)
      page.normalized_url.to_s != page.normalized_final_url.to_s
    end
  end
end
