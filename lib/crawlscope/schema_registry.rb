# frozen_string_literal: true

require "json-schema"

JSON::Validator.use_multi_json = false

module Crawlscope
  class SchemaRegistry
    def initialize(schemas: {})
      @schemas = schemas.transform_keys(&:to_s).dup
    end

    def self.default
      new(schemas: Schemas.schemas)
    end

    def dup
      self.class.new(schemas: deep_copy(@schemas))
    end

    def fetch(type)
      @schemas.fetch(type.to_s)
    end

    def register(type, schema)
      @schemas[type.to_s] = schema
      self
    end

    def registered?(type)
      @schemas.key?(type.to_s)
    end

    def validate(item)
      if item.is_a?(Array)
        return item.flat_map { |entry| validate(entry) }
      end

      errors = []

      if item.is_a?(Hash) && item["@graph"].is_a?(Array)
        item["@graph"].each do |graph_item|
          errors.concat(validate(graph_item))
        end
      end

      type = item.is_a?(Hash) ? item["@type"] : nil
      return errors if type.nil?

      schema = @schemas[type.to_s]
      return errors if schema.nil?

      JSON::Validator.fully_validate(schema, item, errors_as_objects: true).each do |error|
        details = {
          field: error[:fragment].to_s.sub("#/", ""),
          issue: error[:message],
          type: type
        }
        if %w[MaxLength MinLength].include?(error[:failed_attribute])
          value = value_at_fragment(item, error[:fragment])
          details[:length] = value.length if value.is_a?(String)
        end
        errors << details
      end

      errors
    rescue JSON::Schema::ValidationError => error
      [{field: "unknown", issue: error.message, type: type}]
    end

    def to_h
      @schemas.dup
    end

    private

    def value_at_fragment(item, fragment)
      fragment.to_s.delete_prefix("#/").split("/").reduce(item) do |value, key|
        case value
        when Hash
          value[key]
        when Array
          value[key.to_i] if key.match?(/\A\d+\z/)
        end
      end
    end

    def deep_copy(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, entry), copy|
          copy[key] = deep_copy(entry)
        end
      when Array
        value.map { |entry| deep_copy(entry) }
      else
        value
      end
    end
  end
end
