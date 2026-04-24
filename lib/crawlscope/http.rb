# frozen_string_literal: true

require "concurrent"
require "faraday"
require "faraday/follow_redirects"
require "nokogiri"

module Crawlscope
  class Http
    MAX_REDIRECTS = 5
    USER_AGENT = "Mozilla/5.0 (compatible; Crawlscope/1.0)"

    def initialize(base_url:, timeout_seconds:)
      @base_url = base_url
      @timeout_seconds = timeout_seconds
      @connections_by_thread = Concurrent::Map.new
    end

    def close
      @connections_by_thread.clear
    end

    def fetch(url)
      response = connection.get(url) do |request|
        request.headers["User-Agent"] = USER_AGENT
      end

      final_url = response.env.url.to_s
      final_url = url if final_url.empty?
      headers = response.headers.to_h
      body = response.body.to_s
      doc = if response.status == 200 && html_response?(headers)
        Nokogiri::HTML(body)
      end

      Page.new(
        url: url,
        normalized_url: Url.normalize(url, base_url: @base_url),
        final_url: final_url,
        normalized_final_url: Url.normalize(final_url, base_url: @base_url),
        status: response.status,
        headers: headers,
        body: body,
        doc: doc
      )
    rescue Faraday::Error, SocketError, SystemCallError, Timeout::Error => error
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

    def connection
      @connections_by_thread.compute_if_absent(Thread.current.object_id) do
        Faraday.new do |faraday|
          faraday.response :follow_redirects, limit: MAX_REDIRECTS
          faraday.options.timeout = @timeout_seconds
          faraday.options.open_timeout = @timeout_seconds
        end
      end
    end

    def html_response?(headers)
      content_type = headers["content-type"] || headers.find { |key, _value| key.to_s.casecmp("content-type").zero? }&.last.to_s
      content_type.empty? || content_type.include?("text/html")
    end
  end
end
