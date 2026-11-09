# frozen_string_literal: true

module Crawlscope
  module Crawling
    class FetcherFactory
      def initialize(base_url:, renderer:, timeout_seconds:, browser_factory: nil,
        network_idle_timeout_seconds: Configuration::DEFAULT_BROWSER_NETWORK_IDLE_TIMEOUT_SECONDS,
        scroll_page: Configuration::DEFAULT_BROWSER_SCROLL_PAGE, profile_token: nil, adapter: nil)
        @base_url = base_url
        @renderer = renderer
        @timeout_seconds = timeout_seconds
        @browser_factory = browser_factory
        @network_idle_timeout_seconds = network_idle_timeout_seconds
        @scroll_page = scroll_page
        @profile_token = profile_token
        @adapter = adapter
      end

      def call
        return Http.new(base_url: @base_url, timeout_seconds: @timeout_seconds, adapter: @adapter, profile_token: @profile_token) unless @renderer == :browser
        return @browser_factory.call if @browser_factory

        Browser.new(base_url: @base_url, timeout_seconds: @timeout_seconds,
          network_idle_timeout_seconds: @network_idle_timeout_seconds,
          scroll_page: @scroll_page, profile_token: @profile_token)
      rescue LoadError => error
        raise ConfigurationError, "Browser rendering requires the ferrum gem (#{error.message})"
      end
    end
  end
end
