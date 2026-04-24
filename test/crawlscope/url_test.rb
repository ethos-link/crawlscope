# frozen_string_literal: true

require "test_helper"

class CrawlscopeUrlTest < Minitest::Test
  def test_normalize_resolves_relative_urls_and_removes_trailing_slash
    assert_equal "https://example.com/pricing", Crawlscope::Url.normalize("/pricing/", base_url: "https://example.com")
  end

  def test_normalize_preserves_non_default_port
    assert_equal "http://localhost:3000/pricing", Crawlscope::Url.normalize("/pricing", base_url: "http://localhost:3000")
  end

  def test_normalize_for_base_rebases_absolute_urls
    assert_equal(
      "http://localhost:3000/features",
      Crawlscope::Url.normalize_for_base("https://www.example.com/features", base_url: "http://localhost:3000")
    )
  end

  def test_path_normalizes_blank_and_trailing_slash
    assert_equal "/", Crawlscope::Url.path("https://example.com")
    assert_equal "/features", Crawlscope::Url.path("https://example.com/features/")
  end

  def test_invalid_urls_are_returned_or_ignored
    assert_equal "http:// bad", Crawlscope::Url.normalize("http:// bad", base_url: "https://example.com")
    assert_nil Crawlscope::Url.path("http:// bad")
    refute Crawlscope::Url.remote?("http:// bad")
  end
end
