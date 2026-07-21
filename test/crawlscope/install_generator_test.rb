# frozen_string_literal: true

require "test_helper"
require "generators/crawlscope/install_generator"
require "open3"
require "rbconfig"

class CrawlscopeInstallGeneratorTest < Minitest::Test
  def test_generates_lazy_initializer_and_task_loader
    Dir.mktmpdir do |destination|
      File.write(File.join(destination, "Rakefile"), <<~RUBY)
        require_relative "config/application"
        Rails.application.load_tasks
      RUBY

      Crawlscope::Generators::InstallGenerator.start([], destination_root: destination)

      initializer = File.join(destination, "config/initializers/crawlscope.rb")
      rakefile = File.read(File.join(destination, "Rakefile"))

      assert File.exist?(initializer)
      assert_includes File.read(initializer), "module CrawlscopeConfiguration"
      assert_includes File.read(initializer), "CrawlscopeConfiguration.apply if defined?(Crawlscope)"
      assert_includes rakefile, 'require "crawlscope/tasks"'
      assert_operator rakefile.index('require "crawlscope/tasks"'), :<, rakefile.index('require_relative "config/application"')

      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, initializer)
      assert status.success?, stderr

      script = <<~RUBY
        require "pathname"

        module Rails
          def self.public_path
            Pathname.new("public")
          end
        end

        require "crawlscope"
        load ARGV.fetch(0)

        configuration = Crawlscope.configuration
        CrawlscopeConfiguration.apply
        abort "configuration replaced" unless Crawlscope.configuration.equal?(configuration)
        abort "base URL missing" unless configuration.base_url == "http://localhost:3000"
        abort "sitemap missing" unless configuration.sitemap_path == "public/sitemap.xml"
      RUBY
      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        "-I#{File.expand_path("../../lib", __dir__)}",
        "-e",
        script,
        initializer
      )
      assert status.success?, stderr
    end
  end
end
