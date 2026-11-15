# frozen_string_literal: true

module Crawlscope
  module StructuredData
    class Check
      def initialize(configuration:)
        @configuration = configuration
        @required_types = configuration.required_structured_data_types if configuration.respond_to?(:required_structured_data_types)
      end

      def call(urls:, debug: false, renderer: @configuration.renderer, timeout_seconds: @configuration.timeout_seconds, report_path: nil, summary: false)
        result = audit(renderer: renderer, timeout_seconds: timeout_seconds).call(urls: urls)
        reporter = Reporter.new(io: @configuration.output, report_path: report_path)

        reporter.details(result, debug: debug, renderer: renderer)
        Writer.new(path: report_path).write(result) if report_path
        reporter.report(result) if summary

        result
      end

      private

      def audit(renderer:, timeout_seconds:)
        Audit.new(
          browser_factory: @configuration.browser_factory,
          network_idle_timeout_seconds: @configuration.network_idle_timeout_seconds,
          renderer: renderer,
          required_types: @required_types,
          schema_registry: @configuration.schema_registry,
          scroll_page: @configuration.scroll_page?,
          timeout_seconds: timeout_seconds
        )
      end
    end
  end
end
