# frozen_string_literal: true

require "test_helper"

class CrawlscopeRunTest < Minitest::Test
  FakeResult = Data.define(:reported) do
    def ok?
      true
    end
  end

  class FakeReporter
    attr_reader :result

    def report(result)
      @result = result
    end
  end

  class FakeAudit
    def initialize(result:)
      @result = result
    end

    def call
      @result
    end
  end

  class FakeConfiguration
    attr_reader :base_url, :received_arguments, :sitemap_path

    def initialize(result:, base_url: "https://example.com", sitemap_path: "/tmp/sitemap.xml")
      @result = result
      @base_url = base_url
      @sitemap_path = sitemap_path
    end

    def audit(base_url:, sitemap_path:, rule_names:)
      @received_arguments = {
        base_url: base_url,
        sitemap_path: sitemap_path,
        rule_names: rule_names
      }

      FakeAudit.new(result: @result)
    end
  end

  class JsonLdConfiguration
    attr_reader :output

    def initialize(output:, page:)
      @output = output
      @page = page
      @closed = false
    end

    def browser_factory
      -> { self }
    end

    def close
      @closed = true
    end

    def closed?
      @closed
    end

    def fetch(_url)
      @page
    end

    def network_idle_timeout_seconds
      5
    end

    def renderer
      :browser
    end

    def schema_registry
      Crawlscope::SchemaRegistry.default
    end

    def scroll_page?
      false
    end

    def timeout_seconds
      20
    end
  end

  def test_validate_passes_rule_names_to_configuration_audit
    result = FakeResult.new(reported: true)
    configuration = FakeConfiguration.new(result: result)
    reporter = FakeReporter.new

    run = Crawlscope::Run.new(configuration: configuration, reporter: reporter)
    returned_result = run.validate(rule_names: "links")

    assert_equal(
      {
        base_url: "https://example.com",
        sitemap_path: "/tmp/sitemap.xml",
        rule_names: "links"
      },
      configuration.received_arguments
    )
    assert_same result, reporter.result
    assert_same result, returned_result
  end

  def test_validate_defaults_to_base_url_sitemap_when_not_configured
    result = FakeResult.new(reported: true)
    configuration = FakeConfiguration.new(result: result, base_url: "https://example.com", sitemap_path: nil)
    reporter = FakeReporter.new

    Crawlscope::Run.new(configuration: configuration, reporter: reporter).validate

    assert_equal(
      {
        base_url: "https://example.com",
        sitemap_path: "https://example.com/sitemap.xml",
        rule_names: nil
      },
      configuration.received_arguments
    )
  end

  def test_validate_uses_http_sitemap_for_localhost
    result = FakeResult.new(reported: true)
    configuration = FakeConfiguration.new(result: result, base_url: "http://localhost:3000", sitemap_path: nil)
    reporter = FakeReporter.new

    Crawlscope::Run.new(configuration: configuration, reporter: reporter).validate

    assert_equal(
      {
        base_url: "http://localhost:3000",
        sitemap_path: "http://localhost:3000/sitemap.xml",
        rule_names: nil
      },
      configuration.received_arguments
    )
  end

  def test_validate_json_ld_reports_valid_structured_data
    body = <<~HTML
      <html>
        <head>
          <script type="application/ld+json">
            {"@type":"WebSite","name":"Example","url":"https://example.com"}
          </script>
        </head>
      </html>
    HTML
    page = Crawlscope::Page.new(
      url: "https://example.com",
      normalized_url: "https://example.com",
      final_url: "https://example.com",
      normalized_final_url: "https://example.com",
      status: 200,
      headers: {"content-type" => "text/html"},
      body: body,
      doc: nil
    )
    output = StringIO.new
    configuration = JsonLdConfiguration.new(output: output, page: page)
    report_dir = Dir.mktmpdir
    report_path = File.join(report_dir, "structured-data.json")

    result = Crawlscope::Run.new(configuration: configuration).validate_json_ld(
      urls: [page.url],
      debug: true,
      report_path: report_path,
      summary: true
    )

    assert result.ok?
    assert_predicate configuration, :closed?
    assert File.exist?(report_path)
    assert_equal ["https://example.com"], JSON.parse(File.read(report_path)).fetch("results").keys
    assert_includes output.string, "JavaScript mode enabled (Ferrum)"
    assert_includes output.string, "Validating JSON-LD on 1 URL(s)"
    assert_includes output.string, "All valid!"
    assert_includes output.string, "All 1 URLs passed validation."
  ensure
    FileUtils.rm_rf(report_dir) if report_dir
  end
end
