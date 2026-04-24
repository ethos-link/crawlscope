# frozen_string_literal: true

module Crawlscope
  class Configuration
    DEFAULT_ALLOWED_STATUSES = [200, 301, 302].freeze
    DEFAULT_BROWSER_CONCURRENCY = 4
    DEFAULT_BROWSER_NETWORK_IDLE_TIMEOUT_SECONDS = 5
    DEFAULT_BROWSER_SCROLL_PAGE = true
    DEFAULT_CONCURRENCY = 10
    RENDERERS = %i[http browser].freeze
    DEFAULT_TIMEOUT_SECONDS = 20

    attr_writer :allowed_statuses, :base_url, :browser_factory, :concurrency, :network_idle_timeout_seconds, :output, :renderer, :rule_registry, :schema_registry, :scroll_page, :site_name, :sitemap_path, :timeout_seconds

    def allowed_statuses
      value = resolve(@allowed_statuses)
      Array(value.nil? ? DEFAULT_ALLOWED_STATUSES : value).map(&:to_i)
    end

    def base_url
      resolve(@base_url)
    end

    def browser_factory
      resolve(@browser_factory)
    end

    def concurrency
      value = resolve(@concurrency)
      positive_integer(value, default: DEFAULT_CONCURRENCY, name: "concurrency")
    end

    def browser_concurrency
      value = concurrency
      default_value = DEFAULT_BROWSER_CONCURRENCY

      if value > default_value
        default_value
      else
        value
      end
    end

    def network_idle_timeout_seconds
      value = resolve(@network_idle_timeout_seconds)
      positive_integer(value, default: DEFAULT_BROWSER_NETWORK_IDLE_TIMEOUT_SECONDS, name: "network_idle_timeout_seconds")
    end

    def output
      value = resolve(@output)
      value.nil? ? $stdout : value
    end

    def renderer
      value = resolve(@renderer)
      normalized_value = value.to_s.strip
      normalized_value = "http" if normalized_value.empty?

      renderer = normalized_value.to_sym
      return renderer if RENDERERS.include?(renderer)

      raise ConfigurationError, "Crawlscope renderer must be http or browser"
    end

    def rule_registry
      value = resolve(@rule_registry)
      return value unless value.nil?

      RuleRegistry.default(site_name: site_name)
    end

    def audit(base_url: self.base_url, sitemap_path: self.sitemap_path, rule_names: nil)
      if base_url.to_s.strip.empty?
        raise ConfigurationError, "Crawlscope base_url is not configured"
      end

      if sitemap_path.to_s.strip.empty?
        raise ConfigurationError, "Crawlscope sitemap_path is not configured"
      end

      Crawl.new(
        base_url: base_url,
        sitemap_path: sitemap_path,
        browser_factory: browser_factory,
        concurrency: concurrency,
        network_idle_timeout_seconds: network_idle_timeout_seconds,
        renderer: renderer,
        timeout_seconds: timeout_seconds,
        allowed_statuses: allowed_statuses,
        rules: rule_registry.rules_for(rule_names),
        schema_registry: schema_registry,
        scroll_page: scroll_page?
      )
    end

    def schema_registry
      value = resolve(@schema_registry)
      return value unless value.nil?

      SchemaRegistry.default
    end

    def site_name
      resolve(@site_name)
    end

    def scroll_page?
      value = resolve(@scroll_page)
      value.nil? ? DEFAULT_BROWSER_SCROLL_PAGE : value
    end

    def sitemap_path
      resolve(@sitemap_path)
    end

    def timeout_seconds
      value = resolve(@timeout_seconds)
      positive_integer(value, default: DEFAULT_TIMEOUT_SECONDS, name: "timeout_seconds")
    end

    private

    def resolve(value)
      value.respond_to?(:call) ? value.call : value
    end

    def positive_integer(value, default:, name:)
      return default if value.nil?

      integer = value.is_a?(Integer) ? value : Integer(value, 10)
      raise ArgumentError if integer < 1

      integer
    rescue ArgumentError, TypeError
      raise ConfigurationError, "Crawlscope #{name} must be an integer >= 1"
    end
  end
end
