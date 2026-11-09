# frozen_string_literal: true

module Crawlscope
  module StructuredData
    class Validator
      Finding = Data.define(:code, :source, :type, :errors, :paths)
      Validation = Data.define(:items, :findings)

      def initialize(schema_registry:)
        @schema_registry = schema_registry
      end

      def call(html:)
        items = Document.new(html: html).items
        Validation.new(items: items, findings: items.flat_map { |item| validate(item) })
      end

      private

      def validate(item)
        data = item.data
        if data.is_a?(Hash) && data[:error]
          return [finding(:structured_data_parse_error, item, [{field: "parse", issue: data[:message]}])]
        end

        findings = []
        paths = missing_type_paths(data)
        unless paths.empty?
          errors = paths.map { |path| {field: "#{path}.@type", issue: "is required"} }
          findings << finding(:structured_data_missing_type, item, errors, paths)
        end
        errors = @schema_registry.validate(data)
        findings << finding(:structured_data_schema_error, item, errors) unless errors.empty?
        findings
      end

      def finding(code, item, errors, paths = [])
        Finding.new(code: code, source: item.source, type: item.data["@type"] || item.source, errors: errors, paths: paths)
      end

      def missing_type_paths(data, path = "$")
        return [] unless data.is_a?(Hash)

        paths = data["@type"].to_s.strip.empty? ? [path] : []
        if data["@graph"].is_a?(Array)
          data["@graph"].each_with_index do |entry, index|
            paths.concat(missing_type_paths(entry, "#{path}.@graph[#{index}]"))
          end
        end
        paths
      end
    end
  end
end
