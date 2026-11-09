# frozen_string_literal: true

require "uri"

module Crawlscope
  module Reporting
    class UrlFormatter
      def initialize(base_url: nil)
        @base_url = base_url
      end

      def call(url)
        return url unless url && @base_url

        uri = URI.parse(url)
        base_uri = URI.parse(@base_url)

        return url unless uri.host == base_uri.host && uri.scheme == base_uri.scheme && uri.port == base_uri.port

        relative = uri.path.to_s.empty? ? "/" : uri.path
        relative += "?#{uri.query}" if uri.query
        relative += "##{uri.fragment}" if uri.fragment
        relative
      rescue URI::InvalidURIError
        url
      end
    end
  end
end
