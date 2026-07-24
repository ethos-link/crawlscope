# frozen_string_literal: true

module Crawlscope
  class ServerTiming
    class Summary
      WORST_PAGE_LIMIT = 10

      attr_reader :pages

      def initialize(pages)
        @pages = pages
        @timings = pages.filter_map do |page|
          timing = page.server_timing
          [page, timing] if timing.present?
        end
      end

      def present?
        @timings.any?
      end

      def duration_pages
        @timings.count { |_page, timing| timing.any?(&:timed?) }
      end

      def invalid_count
        @timings.sum { |_page, timing| timing.invalid_count }
      end

      def metrics
        timed_metrics
          .group_by { |_page, metric| [metric.name, metric.description] }
          .map { |(name, description), samples| metric_summary(name, description, samples) }
          .sort_by { |metric| [-metric[:p95], -metric[:maximum], metric[:name]] }
      end

      def signals
        all_metrics
          .reject { |_page, metric| metric.timed? }
          .group_by { |_page, metric| [metric.name, metric.description] }
          .map { |(name, description), samples| signal_summary(name, description, samples) }
          .sort_by { |signal| [-signal[:samples], signal[:name], signal[:description].to_s] }
      end

      def worst_pages(limit: WORST_PAGE_LIMIT)
        @timings
          .filter_map { |page, timing| worst_metric(page, timing) }
          .min_by(limit) { |sample| [-sample[:metric].duration, sample[:page].url] }
          .sort_by { |sample| [-sample[:metric].duration, sample[:page].url] }
      end

      def coverage
        @timings.size
      end

      private

      def timed_metrics
        all_metrics.select { |_page, metric| metric.timed? }
      end

      def all_metrics
        @all_metrics ||= @timings.flat_map do |page, timing|
          timing.map { |metric| [page, metric] }
        end
      end

      def metric_summary(name, description, samples)
        durations = samples.map { |_page, metric| metric.duration }.sort

        {
          name: name,
          description: description,
          samples: samples.size,
          pages: samples.map(&:first).uniq.size,
          average: durations.sum.fdiv(durations.size),
          p50: percentile(durations, 0.50),
          p95: percentile(durations, 0.95),
          maximum: durations.last
        }
      end

      def signal_summary(name, description, samples)
        {
          name: name,
          description: description,
          samples: samples.size,
          pages: samples.map(&:first).uniq.size
        }
      end

      def percentile(values, percentile)
        position = (values.size - 1) * percentile
        lower = values[position.floor]
        upper = values[position.ceil]

        lower + (upper - lower) * (position - position.floor)
      end

      def worst_metric(page, timing)
        if (metric = timing.select(&:timed?).max_by(&:duration))
          {page: page, metric: metric}
        end
      end
    end
  end
end
