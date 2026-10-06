# frozen_string_literal: true

require "test_helper"

class CrawlscopeStructuredDataErrorFormatterTest < Minitest::Test
  def test_formats_missing_root_and_nested_fields_from_real_schema_errors
    registry = Crawlscope::SchemaRegistry.default
    errors = registry.validate({"@type" => "WebApplication", "name" => "App", "review" => {"@type" => "Review"}})

    assert_equal "WebApplication.review/reviewRating: is required", format_error(errors.first)
    assert_equal "Article.headline: is required", format_error(registry.validate({"@type" => "Article"}).first)
  end

  def test_preserves_unknown_constraints_without_schema_noise
    error = {"field" => "price", "type" => "Product", "issue" => "The property '#/price' must satisfy a custom constraint in schema 3bdea3a8-461f-5eae-9d73-3243b48b4bc8"}

    assert_equal "Product.price: must satisfy a custom constraint", format_error(error)
    assert_equal "$: Unknown error", format_error({})
  end

  def test_formats_custom_minimum_length_constraint
    registry = Crawlscope::SchemaRegistry.new(schemas: {"Thing" => {type: "object", properties: {name: {type: "string", minLength: 3}}}})
    error = registry.validate({"@type" => "Thing", "name" => "x"}).first

    assert_equal "Thing.name: 1 character; minimum 3", format_error(error)
  end

  def test_formats_measured_headline_length_with_symbol_or_json_keys
    error = Crawlscope::SchemaRegistry.default.validate({"@type" => "Article", "headline" => "é" * 111}).first

    assert_equal "Article.headline: 111 characters; maximum 110", format_error(error)
    assert_equal "Article.headline: 111 characters; maximum 110", format_error(JSON.parse(JSON.generate(error)))
  end

  def test_formats_legacy_length_errors_without_a_measurement
    error = {type: "Article", field: "headline", issue: "The property '#/headline' was not of a maximum string length of 110"}

    assert_equal "Article.headline: exceeds 110 characters", format_error(error)
  end

  private

  def format_error(error)
    Crawlscope::StructuredData::ErrorFormatter.format(error)
  end
end
