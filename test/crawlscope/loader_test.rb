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

      abort "Rails loaded by the core" if defined?(Rails)
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

  def test_explicit_rails_integration_loads_after_the_core_and_registers_tasks
    script = <<~RUBY
      require "crawlscope"
      require "crawlscope/rails"

      abort "Railtie missing" unless Crawlscope::Railtie < Rails::Railtie
      app = Class.new(Rails::Application)
      app.config.eager_load = false
      app.load_tasks
      %w[validate validate:ldjson validate:indexability validate:content_quality].each do |task|
        abort "task missing: \#{task}" unless Rake::Task.task_defined?("crawlscope:\#{task}")
      end
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
