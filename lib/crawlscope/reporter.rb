# frozen_string_literal: true

module Crawlscope
  class Reporter
    def initialize(io:)
      @io = io
    end

    def report(result)
      @io.puts("Crawlscope validation")
      @io.puts("Base URL: #{result.base_url}")
      @io.puts("Sitemap: #{result.sitemap_path}")
      @io.puts("URLs: #{result.urls.size}")
      @io.puts("Pages: #{result.pages.size}")

      if result.ok?
        @io.puts("Status: OK")
        return
      end

      @io.puts("Status: FAILED")
      @io.puts("Issues: #{result.issues.size}")
      @io.puts("")

      report_grouped_issues("Severity", result.issues.by_severity)
      @io.puts("")
      report_grouped_issues("Category", result.issues.by_category)
    end

    private

    def report_grouped_issues(title, grouped_issues)
      @io.puts("#{title}:")

      grouped_issues.sort_by { |name, _issues| name.to_s }.each do |name, issues|
        @io.puts("#{name}: #{issues.size}")
        issues.each do |issue|
          @io.puts("  - #{offense(issue)}")
        end
      end
    end

    def offense(issue)
      parts = ["[#{issue.severity}]", issue.code, issue.url, issue.message]
      parts.compact.join(" ")
    end
  end
end
