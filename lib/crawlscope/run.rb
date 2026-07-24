# frozen_string_literal: true

module Crawlscope
  class Run
    def initialize(configuration: Crawlscope.configuration, reporter: Reporter.new(io: configuration.output))
      @configuration = configuration
      @reporter = reporter
    end

    def validate(base_url: nil, sitemap_path: nil, rule_names: nil)
      resolved_base_url = base_url || default_base_url
      crawl = @configuration.audit(
        base_url: resolved_base_url,
        sitemap_path: sitemap_path || default_sitemap_path(base_url: resolved_base_url),
        rule_names: rule_names
      )

      result = crawl.call
      @reporter.report(result)
      result
    end

    def validate_json_ld(urls:, debug: false, renderer: @configuration.renderer, timeout_seconds: @configuration.timeout_seconds, report_path: nil, summary: false)
      StructuredData::Check.new(configuration: @configuration).call(
        urls: urls,
        debug: debug,
        renderer: renderer,
        timeout_seconds: timeout_seconds,
        report_path: report_path,
        summary: summary
      )
    end

    private

    def default_base_url
      value = @configuration.base_url
      return value unless value.to_s.strip.empty?

      "http://localhost:3000"
    end

    def default_sitemap_path(base_url:)
      value = @configuration.sitemap_path
      return value unless value.to_s.strip.empty?

      "#{base_url.to_s.chomp("/")}/sitemap.xml"
    end
  end
end
