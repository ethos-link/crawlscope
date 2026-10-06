# frozen_string_literal: true

require "uri"
require "json"

module Crawlscope
  module StructuredData
    class Reporter
      def initialize(io:, report_path: nil)
        @io = io
        @report_path = report_path
      end

      def report(result)
        report = Report.new(result)

        if report.all_valid?
          @io.puts("")
          @io.puts("All #{report.total} URLs passed validation.")
        else
          report_failures(report)
        end
      end

      def details(result, debug:, renderer:)
        @io.puts("JavaScript mode enabled (Ferrum)") if renderer == :browser
        @io.puts("Validating JSON-LD on #{result.entries.size} URL(s)")
        @io.puts("")

        result.entries.each do |entry|
          report_entry(entry, debug: debug)
        end

        @io.puts("STATUS: #{result.ok? ? "OK" : "FAILED"}")
      end

      private

      def extract_path(url)
        URI.parse(url).path
      rescue URI::InvalidURIError
        url
      end

      def print_category(name, items)
        return if items.empty?

        @io.puts("#{name} (#{items.size}):")
        items.each { |item| yield item }
        @io.puts("")
      end

      def report_failures(report)
        @io.puts("")
        @io.puts("VALIDATION FAILED (#{report.failure_count}/#{report.total} URLs)")
        @io.puts("")

        print_category("HTTP ERRORS", report.http_errors) do |entry|
          @io.puts("• #{extract_path(entry.url)} (#{entry.status}: #{entry.fetch_error})")
        end

        print_category("MISSING STRUCTURED DATA", report.missing_data) do |entry|
          @io.puts("• #{extract_path(entry.url)}")
        end

        print_category("VALIDATION ERRORS", report.validation_errors) do |entry|
          @io.puts("• #{extract_path(entry.url)}")

          entry.errors.each do |error|
            @io.puts("    #{source_label(error[:source])}:")
            error[:errors].each do |validation_error|
              @io.puts("      - #{ErrorFormatter.format(validation_error)}")
            end
          end
        end

        if @report_path
          @io.puts("Full details available in: #{@report_path}")
        end

        @io.puts("#{report.failure_count} of #{report.total} URLs failed validation.")
      end

      def report_entry(entry, debug:)
        @io.puts("URL: #{entry.url}")

        if entry.fetch_error
          @io.puts("Error: #{entry.fetch_error}")
          @io.puts("")
          return
        end

        report_status(entry)
        @io.puts("Structured data found: #{entry.structured_items.size} (JSON-LD: #{entry.json_ld_count}, Microdata: #{entry.microdata_count})")
        report_debug(entry) if debug && entry.structured_items.any?
        report_validation(entry)
        @io.puts("")
      end

      def report_status(entry)
        if entry.status
          @io.puts("Status: #{entry.status}")
        else
          @io.puts("Status: JS runtime fetch")
        end
      end

      def report_debug(entry)
        @io.puts("")
        @io.puts("--- Detected Structured Data ---")

        entry.structured_items.each_with_index do |item, index|
          @io.puts("")
          @io.puts("## Item #{index + 1} [#{item[:source]}]")
          @io.puts(JSON.pretty_generate(item[:data]))
        end

        @io.puts("")
        @io.puts("--- End ---")
      end

      def report_validation(entry)
        @io.puts("")
        if entry.errors.empty?
          @io.puts("Validation: OK")
        else
          @io.puts("Validation: FAILED")
          entry.errors.each do |error|
            @io.puts("  #{source_label(error[:source])}:")
            error[:errors].each do |validation_error|
              @io.puts("    - #{ErrorFormatter.format(validation_error)}")
            end
          end
        end
      end

      def source_label(source)
        (source == "json-ld") ? "JSON-LD" : source
      end
    end
  end
end
