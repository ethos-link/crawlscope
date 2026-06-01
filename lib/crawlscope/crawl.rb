# frozen_string_literal: true

module Crawlscope
  class Crawl
    def initialize(base_url:, sitemap_path:, rules:, schema_registry:, browser_factory: nil, concurrency: Configuration::DEFAULT_CONCURRENCY, fetch_executor: Configuration::DEFAULT_FETCH_EXECUTOR, network_idle_timeout_seconds: Configuration::DEFAULT_BROWSER_NETWORK_IDLE_TIMEOUT_SECONDS, renderer: :http, scroll_page: Configuration::DEFAULT_BROWSER_SCROLL_PAGE, timeout_seconds: Configuration::DEFAULT_TIMEOUT_SECONDS, allowed_statuses: Configuration::DEFAULT_ALLOWED_STATUSES)
      @base_url = base_url
      @sitemap_path = sitemap_path
      @rules = Array(rules)
      @schema_registry = schema_registry
      @browser_factory = browser_factory
      @concurrency = concurrency
      @fetch_executor = fetch_executor
      @network_idle_timeout_seconds = network_idle_timeout_seconds
      @renderer = renderer.to_sym
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
      cache(pages)
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
        timeout_seconds: @timeout_seconds
      ).urls(base_url: @base_url)
      raise ValidationError, "No URLs found in sitemap: #{@sitemap_path}" if urls.empty?

      urls
    end

    def browser
      Browser.new(
        base_url: @base_url,
        timeout_seconds: @timeout_seconds,
        network_idle_timeout_seconds: @network_idle_timeout_seconds,
        scroll_page: @scroll_page
      )
    rescue LoadError => error
      raise ConfigurationError, "Browser rendering requires the ferrum gem (#{error.message})"
    end

    def page
      if @renderer == :browser
        (@browser_factory || method(:browser)).call
      else
        Http.new(base_url: @base_url, timeout_seconds: @timeout_seconds, adapter: http_adapter)
      end
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
          issues.add(code: :redirected_page, severity: :warning, category: :crawl, url: page.url, message: "redirects to #{page.final_url}", details: {final_url: page.final_url, status: page.status})
          issues.add(code: :sitemap_redirect_url, severity: :warning, category: :sitemaps, url: page.url, message: "sitemap URL redirects to #{page.final_url}", details: {final_url: page.final_url, status: page.status})
        end
      end
    end

    def cache(pages)
      @pages = {}
      @targets = {}

      pages.each do |page|
        cache_page(page)
      end
    end

    def cache_page(page)
      @pages[page.normalized_url] = page unless page.normalized_url.to_s.empty?
      @pages[page.normalized_final_url] = page unless page.normalized_final_url.to_s.empty?
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

    def fetched_pages(normalized_urls)
      return [] if normalized_urls.empty?

      Crawler.new(page_fetcher: @page_fetcher, concurrency: @concurrency, fetch_executor: @fetch_executor).call(normalized_urls)
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

    def redirected?(page)
      page.normalized_url.to_s != page.normalized_final_url.to_s
    end
  end
end
