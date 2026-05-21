# frozen_string_literal: true

module Crawlscope
  class RuleRegistry
    attr_reader :default_codes, :rules

    def initialize(rules:, default_codes: nil)
      @rules = Array(rules)
      @default_codes = Array(default_codes).map(&:to_sym)
    end

    def self.default(site_name: nil)
      new(
        rules: [
          Rules::Indexability.new,
          Rules::Metadata.new(site_name: site_name),
          Rules::StructuredData.new,
          Rules::Uniqueness.new,
          Rules::ContentQuality.new,
          Rules::Links.new
        ],
        default_codes: %i[indexability metadata structured_data uniqueness content_quality links]
      )
    end

    def codes
      @rules.map(&:code)
    end

    def rules_for(names)
      normalized_names = Array(names).flat_map { |value| value.to_s.split(",") }.map(&:strip).reject(&:empty?)
      normalized_names = @default_codes.map(&:to_s) if normalized_names.empty?

      selected_rules = @rules.select { |rule| normalized_names.include?(rule.code.to_s) }
      missing_rules = normalized_names - selected_rules.map { |rule| rule.code.to_s }
      return selected_rules if missing_rules.empty?

      raise ConfigurationError, "Unknown Crawlscope rules: #{missing_rules.join(", ")}"
    end
  end
end
