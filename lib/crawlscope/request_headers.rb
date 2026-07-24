# frozen_string_literal: true

require "uri"

module Crawlscope
  module RequestHeaders
    PROFILE_TOKEN = "X-Profile-Token"

    module_function

    def add_profile_token(headers, url:, base_url:, profile_token:)
      return headers if profile_token.to_s.empty?
      return headers unless same_origin?(url, base_url: base_url)

      headers[PROFILE_TOKEN] = profile_token
      headers
    end

    def strip_profile_token_on_cross_origin_redirect(response_env, request_env)
      return if same_origin?(request_env[:url], base_url: response_env[:url])

      request_env[:request_headers].delete(PROFILE_TOKEN)
    end

    def same_origin?(url, base_url:)
      url_uri = URI.join(base_url.to_s, url.to_s)
      base_uri = URI.parse(base_url.to_s)

      [url_uri.scheme, url_uri.host, url_uri.port] == [base_uri.scheme, base_uri.host, base_uri.port]
    rescue URI::Error
      false
    end
  end
end
