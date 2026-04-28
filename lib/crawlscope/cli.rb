# frozen_string_literal: true

require "optparse"

module Crawlscope
  class Cli
    def self.start(argv, out: $stdout, err: $stderr, **options)
      new(argv, out: out, err: err, **options).call
    end

    def initialize(argv, out:, err:, configuration: Configuration.new, task: nil)
      @argv = Array(argv).dup
      @out = out
      @err = err
      @configuration = configuration
      @configuration.output = out
      @task = task
    end

    def call
      command = @argv.shift.to_s

      case command
      when "help", ""
        @out.puts(general_usage)
        0
      when "validate"
        run_validate
      when "ldjson"
        run_ldjson
      when "version", "--version", "-v"
        @out.puts(Crawlscope::VERSION)
        0
      else
        @err.puts("Unknown command: #{command}")
        @err.puts("")
        @err.puts(general_usage)
        1
      end
    rescue OptionParser::InvalidOption, OptionParser::MissingArgument, ConfigurationError, ValidationError, ArgumentError => error
      @err.puts(error.message)
      @err.puts("")
      @err.puts(general_usage)
      1
    end

    private

    def general_usage
      <<~TEXT
        Usage:
          crawlscope validate --url https://example.com [options]
          crawlscope ldjson --url https://example.com/page [options]
          crawlscope version

        Commands:
          validate    Audit URLs for metadata, structured data, uniqueness, and links
          ldjson      Validate structured data on one or more URLs
          version     Print the gem version
      TEXT
    end

    def run_ldjson
      options = {
        debug: env_enabled?("DEBUG"),
        renderer: resolved_renderer,
        report_path: normalized_string(ENV["REPORT_PATH"]),
        summary: env_enabled?("SUMMARY"),
        timeout_seconds: resolved_integer("TIMEOUT", default: @configuration.timeout_seconds, minimum: 1),
        urls: resolved_urls_from_env
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: crawlscope ldjson --url https://example.com/page [options]"

        opts.on("--url URL", "Validate one URL (repeatable)") do |value|
          options[:urls] << value.strip
        end

        opts.on("--debug", "Print detected structured data") do
          options[:debug] = true
        end

        opts.on("--summary", "Print grouped summary output") do
          options[:summary] = true
        end

        opts.on("--report-path PATH", "Write a JSON report to PATH") do |value|
          options[:report_path] = value
        end

        opts.on("--renderer NAME", "Use http or browser rendering") do |value|
          options[:renderer] = value.to_sym
        end

        opts.on("--timeout SECONDS", Integer, "Set request timeout") do |value|
          options[:timeout_seconds] = integer_option(value, minimum: 1, name: "timeout")
        end

        opts.on("--network-idle-timeout SECONDS", Integer, "Set browser network idle timeout") do |value|
          @configuration.network_idle_timeout_seconds = integer_option(value, minimum: 1, name: "network-idle-timeout")
        end
      end

      parser.parse!(@argv)

      urls = options[:urls].map(&:strip).reject(&:empty?)
      urls = default_urls if urls.empty?
      raise ConfigurationError, "Crawlscope URL is not configured" if urls.empty?

      configure_renderer(options[:renderer])

      result = task.validate_json_ld(
        urls: urls,
        debug: options[:debug],
        renderer: options[:renderer],
        report_path: options[:report_path],
        summary: options[:summary],
        timeout_seconds: options[:timeout_seconds]
      )

      result.ok? ? 0 : 1
    end

    def run_validate
      options = {
        url: normalized_string(ENV["URL"]),
        rule_names: normalized_string(ENV["RULES"]),
        sitemap_path: normalized_string(ENV["SITEMAP"])
      }

      configure_renderer(resolved_renderer)
      @configuration.concurrency = resolved_concurrency
      @configuration.network_idle_timeout_seconds = resolved_integer("NETWORK_IDLE_TIMEOUT", default: @configuration.network_idle_timeout_seconds, minimum: 1)
      @configuration.timeout_seconds = resolved_integer("TIMEOUT", default: @configuration.timeout_seconds, minimum: 1)

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: crawlscope validate --url https://example.com [options]"

        opts.on("--url URL", "Set the site URL") do |value|
          options[:url] = value
        end

        opts.on("--sitemap PATH_OR_URL", "Set the sitemap path or URL") do |value|
          options[:sitemap_path] = value
        end

        opts.on("--rules CSV", "Run a subset of rules, for example metadata,links") do |value|
          options[:rule_names] = value
        end

        opts.on("--renderer NAME", "Use http or browser rendering") do |value|
          configure_renderer(value.to_sym)
        end

        opts.on("--timeout SECONDS", Integer, "Set request timeout") do |value|
          @configuration.timeout_seconds = integer_option(value, minimum: 1, name: "timeout")
        end

        opts.on("--network-idle-timeout SECONDS", Integer, "Set browser network idle timeout") do |value|
          @configuration.network_idle_timeout_seconds = integer_option(value, minimum: 1, name: "network-idle-timeout")
        end

        opts.on("--concurrency COUNT", Integer, "Set crawl concurrency") do |value|
          @configuration.concurrency = integer_option(value, minimum: 1, name: "concurrency")
        end
      end

      parser.parse!(@argv)

      result = task.validate(
        base_url: options[:url],
        sitemap_path: options[:sitemap_path],
        rule_names: options[:rule_names]
      )

      result.ok? ? 0 : 1
    end

    def configure_renderer(renderer)
      @configuration.renderer = renderer
    end

    def env_enabled?(name)
      ENV[name].to_s == "1"
    end

    def integer_option(value, minimum:, name:)
      integer = value.is_a?(Integer) ? value : Integer(value, 10)
      raise ArgumentError, "#{name} must be >= #{minimum}" if integer < minimum

      integer
    rescue ArgumentError => error
      raise error if error.message == "#{name} must be >= #{minimum}"

      raise ArgumentError, "#{name} must be an integer >= #{minimum}"
    end

    def normalized_string(value)
      normalized = value.to_s.strip
      normalized.empty? ? nil : normalized
    end

    def resolved_concurrency
      configured_concurrency = resolved_integer("CONCURRENCY", default: @configuration.concurrency, minimum: 1)

      if @configuration.renderer == :browser && normalized_string(ENV["CONCURRENCY"]).nil?
        browser_concurrency = @configuration.browser_concurrency

        if configured_concurrency > browser_concurrency
          @configuration.output.puts("Default JS concurrency capped at #{browser_concurrency}. Set CONCURRENCY to override.")
          browser_concurrency
        else
          configured_concurrency
        end
      else
        configured_concurrency
      end
    end

    def resolved_integer(name, default:, minimum:)
      raw_value = normalized_string(ENV[name])
      return default if raw_value.nil?

      integer_option(raw_value, minimum: minimum, name: name.downcase.tr("_", "-"))
    end

    def resolved_renderer
      renderer = normalized_string(ENV["RENDERER"])
      return renderer.to_sym if renderer

      env_enabled?("JS") ? :browser : :http
    end

    def resolved_urls_from_env
      raw_urls = normalized_string(ENV["URL"])
      return [] if raw_urls.nil?

      raw_urls.split(";").map(&:strip).reject(&:empty?)
    end

    def default_urls
      [normalized_string(@configuration.base_url) || "http://localhost:3000"]
    end

    def task
      @task ||= Run.new(configuration: @configuration, reporter: Reporter.new(io: @out))
    end
  end
end
