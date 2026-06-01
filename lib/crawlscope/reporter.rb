# frozen_string_literal: true

require "uri"

module Crawlscope
  class Reporter
    MAX_ISSUES_PER_GROUP = 20

    def initialize(io:)
      @io = io
    end

    def report(result)
      @io.puts("Crawlscope validation")
      @io.puts("Base URL: #{result.base_url}")
      @io.puts("Sitemap: #{result.sitemap_path}")
      @io.puts("URLs: #{result.urls.size}")
      @io.puts("Pages: #{result.pages.size}")

      if result.issues.size.zero?
        @io.puts("Status: OK")
        return
      end

      @io.puts("Status: #{status_for(result.issues)}")
      @io.puts("Issues: #{result.issues.size} total (#{severity_summary(result.issues)})")
      @io.puts("")

      report_summary(result.issues)
      @io.puts("")
      report_issue_groups(result.issues, base_url: result.base_url)
    end

    private

    def status_for(issues)
      grouped = issues.by_severity

      if grouped.key?(:error)
        "FAILED"
      elsif grouped.key?(:warning)
        "WARNINGS"
      else
        "NOTICES"
      end
    end

    def severity_summary(issues)
      grouped = issues.by_severity
      return "" if grouped.empty?

      grouped
        .sort_by { |severity, severity_issues| [-severity_issues.size, severity.to_s] }
        .map { |severity, severity_issues| "#{severity_issues.size} #{pluralize(severity, severity_issues.size)}" }
        .join(", ")
    end

    def report_summary(issues)
      @io.puts("Summary:")

      issues.by_category
        .sort_by { |category, category_issues| [-category_issues.size, category.to_s] }
        .each do |category, category_issues|
          @io.puts("  #{category.to_s.ljust(16)} #{category_issues.size}")
        end
    end

    def report_issue_groups(issues, base_url:)
      grouped = issues.to_a.group_by { |issue| [issue.category, issue.code] }

      grouped
        .sort_by { |(category, code), grouped_issues| [-grouped_issues.size, category.to_s, code.to_s] }
        .each do |(category, code), grouped_issues|
          @io.puts("#{category} / #{code}: #{grouped_issues.size}")

          grouped_issues.first(MAX_ISSUES_PER_GROUP).each do |issue|
            @io.puts("  - #{compact_issue(issue, base_url: base_url)}")
          end

          remaining_count = grouped_issues.size - MAX_ISSUES_PER_GROUP
          @io.puts("  ... #{remaining_count} more") if remaining_count.positive?
          @io.puts("")
        end
    end

    def compact_issue(issue, base_url:)
      parts = []
      parts << relative_url(issue.url, base_url: base_url) if issue.url

      detail = compact_detail(issue, base_url: base_url)
      parts << detail unless detail.empty?

      parts.compact.join("  ")
    end

    def compact_detail(issue, base_url:)
      details = issue.details || {}
      fragments = []

      inbound = details[:dofollow_inbound_count] || details[:inbound_count]
      fragments << "inbound #{inbound}/#{details[:minimum]}" if inbound && details[:minimum]

      if details[:ratio] && details[:threshold]
        fragments << "ratio #{format_number(details[:ratio])}/#{format_number(details[:threshold])}"
      end

      fragments << "count #{details[:count]}" if details[:count]
      fragments << "length #{details[:length]}" if details[:length]
      fragments << "status #{details[:status]}" if details[:status]
      fragments << "final: #{relative_url(details[:final_url], base_url: base_url)}" if details[:final_url]
      fragments << "sources: #{relative_urls(details[:source_urls], base_url: base_url).join(", ")}" if details[:source_urls]&.any?
      fragments << "source: #{relative_url(details[:source_url], base_url: base_url)}" if details[:source_url]
      fragments << "targets: #{relative_urls(details[:target_urls], base_url: base_url).join(", ")}" if details[:target_urls]&.any?

      return issue.message if fragments.empty?

      case issue.code
      when :low_dofollow_inlinks, :low_inbound_anchor_links, :low_unique_token_ratio, :low_visible_text_ratio
        fragments.join("  ")
      else
        ([issue.message] + fragments).join("  ")
      end
    end

    def relative_urls(urls, base_url:)
      Array(urls).map { |url| relative_url(url, base_url: base_url) }
    end

    def relative_url(url, base_url:)
      return url unless url && base_url

      uri = URI.parse(url)
      base_uri = URI.parse(base_url)

      return url unless uri.host == base_uri.host && uri.scheme == base_uri.scheme && uri.port == base_uri.port

      relative = uri.path.to_s.empty? ? "/" : uri.path
      relative += "?#{uri.query}" if uri.query
      relative += "##{uri.fragment}" if uri.fragment
      relative
    rescue URI::InvalidURIError
      url
    end

    def format_number(value)
      return format("%.3f", value) if value.is_a?(Float)

      value.to_s
    end

    def pluralize(word, count)
      return word.to_s if count == 1

      "#{word}s"
    end
  end
end
