# frozen_string_literal: true

module Crawlscope
  module Rules
    class StructuredData
      attr_reader :code

      def initialize
        @code = :structured_data
      end

      def call(urls:, pages:, issues:, context:)
        schema_registry = context.fetch(:schema_registry)

        pages.each do |page|
          next unless page.html?

          validate_page(page, issues, schema_registry)
        end
      end

      private

      def validate_page(page, issues, schema_registry)
        document = Crawlscope::StructuredData::Document.new(html: page.body)
        items = document.items

        if items.empty?
          issues.add(
            code: :missing_structured_data,
            severity: :warning,
            category: :structured_data,
            url: page.url,
            message: "no structured data found; add JSON-LD or microdata markup",
            details: {expected_sources: ["json-ld", "microdata"]}
          )
          return
        end

        items.each do |item|
          data = item.data
          source = item.source

          if data.is_a?(Hash) && data[:error]
            issues.add(
              code: :structured_data_parse_error,
              severity: :warning,
              category: :structured_data,
              url: page.url,
              message: "#{source} parse error: #{data[:message]}",
              details: {source: source}
            )
            next
          end

          errors = schema_registry.validate(data)
          next if errors.empty?

          issues.add(
            code: :structured_data_schema_error,
            severity: :warning,
            category: :structured_data,
            url: page.url,
            message: "#{source} schema errors: #{errors.to_json}",
            details: {errors: errors, source: source}
          )
        end
      end
    end
  end
end
