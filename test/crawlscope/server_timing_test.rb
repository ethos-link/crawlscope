# frozen_string_literal: true

require "test_helper"

class CrawlscopeServerTimingTest < Minitest::Test
  def test_parses_metrics_durations_descriptions_and_unknown_parameters
    timing = Crawlscope::ServerTiming.new(
      'miss, db;dur=53, cache;desc="Cache Read";dur=23.2;region=atl'
    )

    assert timing.present?
    assert_equal 0, timing.invalid_count
    assert_equal %w[miss db cache], timing.map(&:name)

    cache = timing.to_a.last
    assert_equal 23.2, cache.duration
    assert_equal "Cache Read", cache.description
  end

  def test_preserves_duplicate_metrics_and_uses_the_first_duplicate_parameter
    timing = Crawlscope::ServerTiming.new(
      ["db;DUR=10;dur=20", "db;dur=30"]
    )

    assert_equal [10.0, 30.0], timing.map(&:duration)
    assert_equal 0, timing.invalid_count
  end

  def test_parses_rails_notification_names
    timing = Crawlscope::ServerTiming.new(
      "sql.active_record;dur=82.4, " \
      "render_template.action_view;dur=10.2, " \
      "process_action.action_controller;dur=101.5"
    )

    assert_equal(
      %w[
        sql.active_record
        render_template.action_view
        process_action.action_controller
      ],
      timing.map(&:name)
    )
    assert_equal 0, timing.invalid_count
  end

  def test_handles_delimiters_and_escapes_inside_quoted_descriptions
    timing = Crawlscope::ServerTiming.new(
      'cache;desc="Cache, read; \\"fast\\"";dur=23.2'
    )

    assert_equal 1, timing.size
    assert_equal 'Cache, read; "fast"', timing.first.description
    assert_equal 0, timing.invalid_count
  end

  def test_reports_invalid_entries_without_discarding_valid_metrics
    timing = Crawlscope::ServerTiming.new(
      "bad metric;dur=2, db;dur=nope, app;dur=3, cache;broken"
    )

    assert_equal %w[app cache], timing.map(&:name)
    assert_equal 3.0, timing.first.duration
    assert_equal 2, timing.invalid_count
  end

  def test_rejects_malformed_standard_parameters
    timing = Crawlscope::ServerTiming.new(
      "db;dur, cache;desc=not quoted, app;dur=3"
    )

    assert_equal ["app"], timing.map(&:name)
    assert_equal 2, timing.invalid_count
  end

  def test_keeps_complete_metrics_before_an_unterminated_description
    timing = Crawlscope::ServerTiming.new(
      'db;dur=5, cache;desc="unterminated'
    )

    assert_equal ["db"], timing.map(&:name)
    assert_equal 1, timing.invalid_count
  end

  def test_ignores_empty_list_members
    timing = Crawlscope::ServerTiming.new(", db;dur=5, , app;dur=3,")

    assert_equal %w[db app], timing.map(&:name)
    assert_equal 0, timing.invalid_count
  end

  def test_distinguishes_an_absent_header_from_an_empty_header
    refute Crawlscope::ServerTiming.new(nil).present?

    timing = Crawlscope::ServerTiming.new("")

    assert timing.present?
    assert_empty timing
    assert_equal 0, timing.invalid_count
  end
end
