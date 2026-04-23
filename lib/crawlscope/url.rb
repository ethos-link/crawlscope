# frozen_string_literal: true

require "uri"

module Crawlscope
  module Url
    module_function

    def normalize(url, base_url:)
      uri = URI.parse(url.to_s)
      uri = URI.join(base_url.to_s, url.to_s) if uri.host.nil?

      normalized_path = uri.path.to_s
      normalized_path = "/" if normalized_path.empty?
      normalized_path = normalized_path.chomp("/")
      normalized_path = "/" if normalized_path.empty?

      host = uri.host.to_s
      host = "#{host}:#{uri.port}" if uri.port && uri.port != uri.default_port

      "#{uri.scheme}://#{host}#{normalized_path}"
    rescue URI::InvalidURIError
      url.to_s
    end

    def normalize_for_base(url, base_url:)
      uri = URI.parse(normalize(url, base_url: base_url))
      base_uri = URI.parse(base_url.to_s)
      unless base_uri.host.to_s.empty?
        uri.scheme = base_uri.scheme
        uri.host = base_uri.host
        uri.port = base_uri.port
      end

      normalize(uri.to_s, base_url: base_url)
    rescue URI::InvalidURIError
      url.to_s
    end

    def path(url)
      uri = URI.parse(url.to_s)
      value = uri.path.to_s
      value = "/" if value.empty?
      value = value.chomp("/")
      value.empty? ? "/" : value
    rescue URI::InvalidURIError
      nil
    end

    def remote?(value)
      uri = URI.parse(value.to_s)
      !uri.scheme.nil? && !uri.host.nil?
    rescue URI::InvalidURIError
      false
    end
  end
end
