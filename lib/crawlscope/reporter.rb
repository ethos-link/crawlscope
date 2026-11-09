# frozen_string_literal: true

module Crawlscope
  class Reporter
    GROUP_LABELS = Reporting::IssuePresenter::GROUP_LABELS

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
      else
        @io.puts("Status: #{status_for(result.issues)}")
        @io.puts("Issues: #{result.issues.size} total (#{severity_summary(result.issues)})")
      end

      unless result.issues.size.zero?
        @io.puts("")
        report_issue_groups(result.issues, base_url: result.base_url)
      end

      ServerTiming::Reporter.new(io: @io).report(result.server_timing_summary, base_url: result.base_url)
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
      severity_summary_for(issues.to_a)
    end

    def report_issue_groups(issues, base_url:)
      grouped = issues.to_a.group_by { |issue| [issue.category, issue.code] }

      grouped
        .sort_by { |(category, code), grouped_issues| [grouped_issues.map { |issue| severity_order(issue.severity) }.min, -grouped_issues.size, category.to_s, code.to_s] }
        .each do |(category, code), grouped_issues|
          label = Reporting::IssuePresenter.label(code)
          @io.puts("#{category.to_s.tr("_", " ").capitalize}: #{label} (#{severity_summary_for(grouped_issues)})")

          urls = Reporting::UrlFormatter.new(base_url: base_url)
          grouped_issues.each do |issue|
            first, *related = Reporting::IssuePresenter.new(issue, urls: urls).lines
            @io.puts("  - #{first}")
            related.each { |line| @io.puts("      #{line}") }
          end

          @io.puts("")
        end
    end

    def severity_order(severity)
      {error: 0, warning: 1, notice: 2}.fetch(severity, 3)
    end

    def severity_summary_for(issues)
      issues.group_by(&:severity).sort_by { |severity, _| severity_order(severity) }
        .map { |severity, entries| "#{entries.size} #{pluralize(severity, entries.size)}" }.join(", ")
    end

    def pluralize(word, count)
      return word.to_s if count == 1

      "#{word}s"
    end
  end
end
