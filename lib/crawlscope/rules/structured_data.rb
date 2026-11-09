# frozen_string_literal: true

module Crawlscope
  module Rules
    class StructuredData
      attr_reader :code

      def initialize(job_posting_path: nil)
        @job_posting_path = job_posting_path
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
        validation = Crawlscope::StructuredData::Validator.new(schema_registry: schema_registry).call(html: page.body)
        items = validation.items

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

        validation.findings.each do |finding|
          details = {source: finding.source}
          message = case finding.code
          when :structured_data_parse_error
            "#{source_label(finding.source)} parse error: #{finding.errors.first[:issue]}"
          when :structured_data_missing_type
            details[:paths] = finding.paths
            "#{source_label(finding.source)} structured data missing @type"
          else
            details[:errors] = finding.errors
            schema_error_message(finding.source, finding.errors)
          end
          issues.add(code: finding.code, severity: :warning, category: :structured_data,
            url: page.url, message: message, details: details)
        end

        validate_job_posting_count(page, items, issues) if @job_posting_path && career_detail_page?(page.url)
      end

      def source_label(source)
        (source == "json-ld") ? "JSON-LD" : source
      end

      def schema_error_message(source, errors)
        messages = errors.map { |error| Crawlscope::StructuredData::ErrorFormatter.format(error) }
        "#{source_label(source)} #{messages.join("; ")}"
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
            message: "JobPosting blocks: #{job_postings.size}; expected 1",
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

      def structured_data_types(data)
        return [] unless data.is_a?(Hash)

        types = Array(data["@type"]).map(&:to_s)

        if data["@graph"].is_a?(Array)
          types.concat(data["@graph"].flat_map { |entry| structured_data_types(entry) })
        end

        types
      end

      def career_detail_page?(url)
        URI(url).path.match?(@job_posting_path)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
