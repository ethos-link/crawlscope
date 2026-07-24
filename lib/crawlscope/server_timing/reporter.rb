# frozen_string_literal: true

require "uri"

module Crawlscope
  class ServerTiming
    class Reporter
      def initialize(io:)
        @io = io
      end

      def report(summary, base_url:)
        return unless summary.present?

        @io.puts("")
        @io.puts("Server Timing:")
        @io.puts(
          "  Coverage: #{summary.coverage}/#{summary.pages.size} pages " \
          "(#{percentage(summary.coverage, summary.pages.size)}); " \
          "durations on #{summary.duration_pages} #{pluralize(:page, summary.duration_pages)}"
        )

        report_metrics(summary.metrics)
        report_signals(summary.signals)
        report_worst_pages(summary.worst_pages, base_url: base_url)
        @io.puts("  Ignored malformed entries: #{summary.invalid_count}") if summary.invalid_count.positive?
      end

      private

      def report_metrics(metrics)
        return if metrics.empty?

        @io.puts("  Duration metrics (dur; milliseconds assumed):")
        metrics.each do |metric|
          label = metric[:name]
          label += " #{description(metric[:description])}" if metric[:description]

          @io.puts(
            "    #{label}: " \
            "#{metric[:samples]} #{pluralize(:sample, metric[:samples])} / " \
            "#{metric[:pages]} #{pluralize(:page, metric[:pages])}; " \
            "avg #{duration(metric[:average])}; " \
            "p50 #{duration(metric[:p50])}; " \
            "p95 #{duration(metric[:p95])}; " \
            "max #{duration(metric[:maximum])}"
          )
        end
      end

      def report_signals(signals)
        return if signals.empty?

        @io.puts("  Signals:")
        signals.each do |signal|
          label = signal[:name]
          label += " #{description(signal[:description])}" if signal[:description]

          @io.puts(
            "    #{label}: " \
            "#{signal[:samples]} #{pluralize(:sample, signal[:samples])} / " \
            "#{signal[:pages]} #{pluralize(:page, signal[:pages])}"
          )
        end
      end

      def report_worst_pages(samples, base_url:)
        return if samples.empty?

        @io.puts("  Worst pages:")
        samples.each do |sample|
          metric = sample[:metric]
          detail = metric.description ? " #{description(metric.description)}" : ""
          @io.puts(
            "    #{relative_url(sample[:page].url, base_url: base_url)}: " \
            "#{duration(metric.duration)} (#{metric.name}#{detail})"
          )
        end
      end

      def duration(value)
        "#{format("%.3f", value).sub(/\.?0+\z/, "")}ms"
      end

      def description(value)
        value = value.to_s
        value = "#{value[0, 77]}..." if value.length > 80
        value.inspect
      end

      def percentage(numerator, denominator)
        return "0.0%" if denominator.zero?

        format("%.1f%%", numerator.fdiv(denominator) * 100)
      end

      def relative_url(url, base_url:)
        uri = URI.parse(url)
        base_uri = URI.parse(base_url)
        return url unless uri.host == base_uri.host && uri.scheme == base_uri.scheme && uri.port == base_uri.port

        uri.request_uri
      rescue URI::InvalidURIError
        url
      end

      def pluralize(word, count)
        (count == 1) ? word.to_s : "#{word}s"
      end
    end
  end
end
