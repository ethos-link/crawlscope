# frozen_string_literal: true

require "nokogiri"

module Crawlscope
  class Browser
    def initialize(base_url:, timeout_seconds:, network_idle_timeout_seconds:, scroll_page:, profile_token: nil)
      @base_url = base_url
      @timeout_seconds = timeout_seconds
      @network_idle_timeout_seconds = network_idle_timeout_seconds
      @profile_token = profile_token
      @scroll_page = scroll_page
      @browser = build_browser
      @page = @browser.create_page
      configure_profile_requests
    end

    def close
      @browser&.quit
    end

    def fetch(url)
      @page.network.clear(:traffic)
      @page.go_to(url)
      wait_for_network_idle

      if @scroll_page
        scroll_for_render
      end

      response = @page.network.response
      final_url = response&.url.to_s
      final_url = @page.current_url.to_s if final_url.empty?
      final_url = @page.url.to_s if final_url.empty?
      final_url = url if final_url.empty?
      headers = response&.headers || {}
      body = @page.body

      Page.new(
        url: url,
        normalized_url: Url.normalize(url, base_url: @base_url),
        final_url: final_url,
        normalized_final_url: Url.normalize(final_url, base_url: @base_url),
        status: @page.network.status,
        headers: headers,
        body: body,
        doc: Nokogiri::HTML(body)
      )
    rescue => error
      raise unless browser_error?(error)

      Page.new(
        url: url,
        normalized_url: Url.normalize(url, base_url: @base_url),
        final_url: url,
        normalized_final_url: Url.normalize(url, base_url: @base_url),
        status: nil,
        headers: {},
        body: nil,
        doc: nil,
        error: "#{error.class}: #{error.message}"
      )
    end

    private

    def build_browser
      require "ferrum"

      Ferrum::Browser.new(
        headless: true,
        timeout: @timeout_seconds,
        headers: {"User-Agent" => Http::USER_AGENT}
      )
    end

    def configure_profile_requests
      return if @profile_token.to_s.empty?

      @page.network.intercept(resource_type: :document)
      @page.on(:request) do |request|
        headers = RequestHeaders.add_profile_token(
          request.headers.dup,
          url: request.url,
          base_url: @base_url,
          profile_token: @profile_token
        )
        request.continue(headers: headers.map { |name, value| {name: name.to_s, value: value.to_s} })
      end
    end

    def scroll_for_render
      @page.evaluate("(function() { if (document.body) { window.scrollTo(0, document.body.scrollHeight); } })()")
      wait_for_network_idle
      @page.evaluate("(function() { if (document.body) { window.scrollTo(0, 0); } })()")
      wait_for_network_idle
      @page.evaluate("(function() { if (document.body) { window.scrollTo(0, document.body.scrollHeight / 2); } })()")
      wait_for_network_idle
    end

    def wait_for_network_idle
      @page.network.wait_for_idle(duration: 0.5, timeout: @network_idle_timeout_seconds)
    rescue Ferrum::TimeoutError
      raise Timeout::Error, "Timed out waiting for browser network idle"
    end

    def browser_error?(error)
      error.is_a?(Timeout::Error) ||
        error.is_a?(SystemCallError) ||
        error.class.name.to_s.start_with?("Ferrum::")
    end
  end
end
