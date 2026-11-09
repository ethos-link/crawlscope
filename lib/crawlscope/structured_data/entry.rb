# frozen_string_literal: true

module Crawlscope
  module StructuredData
    Entry = Data.define(:url, :status, :structured_items, :errors, :fetch_error, :content_type, :skipped_reason) do
      def json_ld_count
        structured_items.count { |item| item[:source] == "json-ld" }
      end

      def microdata_count
        structured_items.count { |item| item[:source] == "microdata" }
      end

      def ok?
        failure_kind.nil?
      end

      def failure_kind
        return :http if fetch_error
        return :missing_data unless structured_data_found?
        return :validation if errors.any?

        nil
      end

      def structured_data_found?
        skipped_reason == "non-html" || structured_items.any?
      end
    end
  end
end
