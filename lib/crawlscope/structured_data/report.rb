# frozen_string_literal: true

module Crawlscope
  module StructuredData
    class Report
      def initialize(result)
        @result = result
      end

      def all_valid?
        @result.ok?
      end

      def failure_count
        entries.count { |entry| !entry.ok? }
      end

      def http_errors
        entries.select { |entry| entry.failure_kind == :http }
      end

      def missing_data
        entries.select { |entry| entry.failure_kind == :missing_data }
      end

      def results
        entries.each_with_object({}) do |entry, collection|
          collection[entry.url] = result_for(entry)
        end
      end

      def total
        entries.size
      end

      def validation_errors
        entries.select { |entry| entry.failure_kind == :validation }
      end

      private

      def entries
        @result.entries
      end

      def result_for(entry)
        if entry.fetch_error
          {
            status: entry.status || "exception",
            error: entry.fetch_error,
            structured_data_found: false,
            validation_errors: [],
            json_ld_count: 0
          }
        else
          {
            status: entry.status || 200,
            error: nil,
            structured_data_found: entry.structured_data_found?,
            validation_errors: entry.errors.flat_map { |error| error[:errors] },
            json_ld_count: entry.json_ld_count,
            skipped_reason: entry.skipped_reason,
            content_type: entry.content_type
          }.compact
        end
      end
    end
  end
end
