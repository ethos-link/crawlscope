# frozen_string_literal: true

module Crawlscope
  module Rules
    class Links
      class UrlChecks
        def initialize(base_url:)
          @base_url = base_url
        end

        def call(urls:, links:, issues:)
          checked_urls = urls.map { |url| Url.normalize(url, base_url: @base_url) }
          checked_urls.concat(links.map { |link| link[:target_url] })

          checked_urls.compact.uniq.each do |url|
            report_url_double_slash(url, issues)
            report_url_too_long(url, issues)
          end
        end

        private

        def report_url_double_slash(url, issues)
          path = URI.parse(url).path.to_s
          return unless path.match?(%r{//+})

          issues.add(
            code: :url_double_slash,
            severity: :notice,
            category: :url,
            url: url,
            message: "URL path contains duplicate slashes",
            details: {path: path}
          )
        rescue URI::InvalidURIError
          nil
        end

        def report_url_too_long(url, issues)
          return unless url.length > 2_048

          issues.add(
            code: :url_too_long,
            severity: :notice,
            category: :url,
            url: url,
            message: "URL: #{url.length} characters; maximum 2048",
            details: {length: url.length, maximum: 2_048}
          )
        end
      end
    end
  end
end
