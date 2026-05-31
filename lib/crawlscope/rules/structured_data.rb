# frozen_string_literal: true

module Crawlscope
  module Rules
    class StructuredData
      CAREER_DETAIL_PATH = %r{/careers/[^/]+/?\z}

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

          validate_type_presence(page, source, data, issues)

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

        validate_job_posting_count(page, items, issues)
      end

      def validate_job_posting_count(page, items, issues)
        job_postings = items.select { |item| structured_data_types(item.data).include?("JobPosting") }
        return if job_postings.size == 1

        if job_postings.size > 1
          issues.add(
            code: :multiple_job_postings,
            severity: :warning,
            category: :structured_data,
            url: page.url,
            message: "multiple JobPosting structured data blocks found",
            details: {count: job_postings.size}
          )
        elsif career_detail_page?(page.url)
          issues.add(
            code: :missing_job_posting,
            severity: :warning,
            category: :structured_data,
            url: page.url,
            message: "career detail page missing JobPosting structured data",
            details: {expected_type: "JobPosting"}
          )
        end
      end

      def validate_type_presence(page, source, data, issues)
        missing_paths = missing_type_paths(data)
        return if missing_paths.empty?

        issues.add(
          code: :structured_data_missing_type,
          severity: :warning,
          category: :structured_data,
          url: page.url,
          message: "#{source} structured data missing @type",
          details: {paths: missing_paths, source: source}
        )
      end

      def missing_type_paths(data, path = "$")
        return [] unless data.is_a?(Hash)

        paths = []
        paths << path if data["@type"].to_s.strip.empty?

        if data["@graph"].is_a?(Array)
          data["@graph"].each_with_index do |entry, index|
            paths.concat(missing_type_paths(entry, "#{path}.@graph[#{index}]"))
          end
        end

        paths
      end

      def structured_data_types(data)
        return [] unless data.is_a?(Hash)

        types = Array(data["@type"]).map(&:to_s)

        if data["@graph"].is_a?(Array)
          types.concat(data["@graph"].flat_map { |entry| structured_data_types(entry) })
        end

        types
      end

      def career_detail_page?(url)
        URI(url).path.match?(CAREER_DETAIL_PATH)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
