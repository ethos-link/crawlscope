# frozen_string_literal: true

require "test_helper"

class CrawlkitSchemaRegistryTest < Minitest::Test
  def test_registers_and_fetches_schema_by_type
    registry = Crawlkit::SchemaRegistry.default
    schema = {"type" => "object"}

    registry.register("Article", schema)

    assert registry.registered?("Article")
    assert_equal schema, registry.fetch("Article")
  end

  def test_dup_copies_registered_schemas
    registry = Crawlkit::SchemaRegistry.new(schemas: {"ThingOne" => {"type" => "object"}})

    copy = registry.dup
    copy.register("ThingTwo", {"type" => "object"})

    assert registry.registered?("ThingOne")
    refute registry.registered?("ThingTwo")
    assert copy.registered?("ThingTwo")
  end

  def test_validate_reports_default_schema_errors
    errors = Crawlkit::SchemaRegistry.default.validate(
      {
        "@context" => "https://schema.org",
        "@type" => "Article"
      }
    )

    assert_predicate errors, :any?
    assert_equal "Article", errors.first[:type]
    assert_includes errors.first[:issue], "headline"
  end

  def test_default_registry_includes_extended_schema_types
    registry = Crawlkit::SchemaRegistry.default

    assert registry.registered?("HowTo")
    assert registry.registered?("Recipe")
    assert registry.registered?("Event")
    assert registry.registered?("VideoObject")
  end

  def test_web_application_review_requires_review_rating
    errors = Crawlkit::SchemaRegistry.default.validate(
      {
        "@context" => "https://schema.org",
        "@type" => "WebApplication",
        "name" => "ROI Calculator",
        "url" => "https://example.com/tools/uplift",
        "review" => {
          "@type" => "Review",
          "reviewBody" => "Helpful tool."
        }
      }
    )

    assert errors.any? { |error| error[:issue].include?("did not contain a required property of 'reviewRating'") }
  end

  def test_product_allows_image_object_variants
    errors = Crawlkit::SchemaRegistry.default.validate(
      {
        "@context" => "https://schema.org",
        "@type" => "Product",
        "name" => "Example Product",
        "image" => {
          "@type" => "ImageObject",
          "url" => "https://example.com/image.png"
        }
      }
    )

    assert_empty errors
  end

  def test_rule_registry_raises_for_unknown_rules
    error = assert_raises(Crawlkit::ConfigurationError) do
      Crawlkit::RuleRegistry.default.rules_for("metadata,unknown")
    end

    assert_equal "Unknown Crawlkit rules: unknown", error.message
  end
end
