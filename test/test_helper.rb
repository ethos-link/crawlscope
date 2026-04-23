# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  add_filter "/test/"
end

require "minitest/autorun"
require "tmpdir"
require "date"
require "fileutils"
require "nokogiri"
require "webmock/minitest"

require "crawlkit"

if defined?(JSON::Validator)
  JSON::Validator.use_multi_json = false
end
