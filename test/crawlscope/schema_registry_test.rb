# frozen_string_literal: true

require "test_helper"

class CrawlscopeSchemaRegistryTest < Minitest::Test
  def test_registers_and_fetches_schema_by_type
    registry = Crawlscope::SchemaRegistry.default
    schema = {"type" => "object"}

    registry.register("Article", schema)

    assert registry.registered?("Article")
    assert_equal schema, registry.fetch("Article")
  end

  def test_dup_copies_registered_schemas
    registry = Crawlscope::SchemaRegistry.new(schemas: {"ThingOne" => {"type" => "object"}})

    copy = registry.dup
    copy.register("ThingTwo", {"type" => "object"})

    assert registry.registered?("ThingOne")
    refute registry.registered?("ThingTwo")
    assert copy.registered?("ThingTwo")
  end

  def test_validate_reports_default_schema_errors
    errors = Crawlscope::SchemaRegistry.default.validate(
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
    registry = Crawlscope::SchemaRegistry.default

    assert registry.registered?("HowTo")
    assert registry.registered?("Recipe")
    assert registry.registered?("Event")
    assert registry.registered?("VideoObject")
  end

  def test_length_errors_include_character_count_without_copying_the_value
    error = Crawlscope::SchemaRegistry.default.validate({"@type" => "Article", "headline" => "é" * 111}).first

    assert_equal 111, error[:length]
    assert_equal "headline", error[:field]
    assert_includes error[:issue], "maximum string length of 110"
    assert_equal [:field, :issue, :type, :length], error.keys
  end

  def test_measures_string_fields_inside_nested_arrays
    schema = {
      type: "object",
      properties: {
        entries: {type: "array", items: {type: "object", properties: {name: {type: "string", maxLength: 3}}}}
      }
    }
    registry = Crawlscope::SchemaRegistry.new(schemas: {"Thing" => schema})
    errors = registry.validate({"@type" => "Thing", "entries" => [{"name" => "ok"}, {"name" => "éééé"}]})

    assert_equal 1, errors.size
    assert_equal "entries/1/name", errors.first[:field]
    assert_equal 4, errors.first[:length]
  end

  def test_measures_each_graph_items_headline_independently
    errors = Crawlscope::SchemaRegistry.default.validate({"@graph" => [
      {"@type" => "Article", "headline" => "a" * 111},
      {"@type" => "Article", "headline" => "b" * 125}
    ]})

    assert_equal [111, 125], errors.map { |error| error[:length] }
  end

  def test_web_application_review_requires_review_rating
    errors = Crawlscope::SchemaRegistry.default.validate(
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
    errors = Crawlscope::SchemaRegistry.default.validate(
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
    error = assert_raises(Crawlscope::ConfigurationError) do
      Crawlscope::RuleRegistry.default.rules_for("metadata,unknown")
    end

    assert_equal "Unknown Crawlscope rules: unknown", error.message
  end

  def test_validate_accepts_arrays_graphs_unknown_types_and_non_hashes
    registry = Crawlscope::SchemaRegistry.default

    errors = registry.validate(
      [
        "ignored",
        {"@type" => "UnknownThing"},
        {
          "@graph" => [
            {"@type" => "Article"},
            {"@type" => "WebSite", "name" => "Example"}
          ]
        }
      ]
    )

    assert_equal ["Article"], errors.map { |error| error[:type] }
  end
end
