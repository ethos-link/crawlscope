# frozen_string_literal: true

require "test_helper"

class CrawlscopeRuleRegistryTest < Minitest::Test
  Rule = Data.define(:code)

  def test_rules_for_returns_defaults_when_names_are_blank
    metadata = Rule.new(:metadata)
    links = Rule.new(:links)
    registry = Crawlscope::RuleRegistry.new(rules: [metadata, links], default_codes: %i[links])

    assert_equal [links], registry.rules_for(nil)
    assert_equal [links], registry.rules_for("")
  end

  def test_rules_for_accepts_csv_and_arrays
    metadata = Rule.new(:metadata)
    links = Rule.new(:links)
    registry = Crawlscope::RuleRegistry.new(rules: [metadata, links])

    assert_equal [metadata, links], registry.rules_for(["metadata, links"])
  end

  def test_rules_for_rejects_unknown_rules
    registry = Crawlscope::RuleRegistry.new(rules: [Rule.new(:metadata)])

    error = assert_raises(Crawlscope::ConfigurationError) { registry.rules_for("links") }

    assert_equal "Unknown Crawlscope rules: links", error.message
  end
end
