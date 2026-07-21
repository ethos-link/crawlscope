# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class CrawlscopeLoaderTest < Minitest::Test
  def test_eager_loads_cleanly
    assert_silent do
      Crawlscope.loader.eager_load
    end
  end

  def test_entrypoint_does_not_load_crawl_dependencies
    script = <<~RUBY
      require "crawlscope"

      loaded = $LOADED_FEATURES.grep(%r{/(?:async|faraday|json-schema|nokogiri)(?:/|\\.rb)})
      abort loaded.join("\\n") unless loaded.empty?
    RUBY

    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      "-I#{File.expand_path("../../lib", __dir__)}",
      "-e",
      script
    )

    assert status.success?, stderr
  end

  def test_task_entrypoint_registers_tasks
    script = <<~RUBY
      require "crawlscope/tasks"

      abort "task missing" unless Rake::Task.task_defined?("crawlscope:validate")
    RUBY

    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      "-I#{File.expand_path("../../lib", __dir__)}",
      "-e",
      script
    )

    assert status.success?, stderr
  end
end
