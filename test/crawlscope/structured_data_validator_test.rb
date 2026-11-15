# frozen_string_literal: true

require "test_helper"

class CrawlscopeStructuredDataValidatorTest < Minitest::Test
  def test_requires_every_type_group
    validator = Crawlscope::StructuredData::Validator.new(schema_registry: Crawlscope::SchemaRegistry.default)
    html = '<script type="application/ld+json">{"@type":"WebPage","name":"Benchmark"}</script>'

    result = validator.call(html: html, required_types: ["WebPage", "Dataset"])

    assert_equal [:structured_data_missing_required_type], result.findings.map(&:code)
    assert_equal ["Dataset"], result.findings.first.errors.first.fetch(:expected_types)
  end

  def test_microdata_satisfies_type_requirements
    validator = Crawlscope::StructuredData::Validator.new(schema_registry: Crawlscope::SchemaRegistry.default)
    html = '<article itemscope itemtype="https://schema.org/Article"><h1 itemprop="headline">A guide</h1></article>'

    result = validator.call(html: html, required_types: [["Article", "BlogPosting", "NewsArticle"]])

    assert_empty result.findings
  end
end
