# frozen_string_literal: true

require "test_helper"

class CrawlscopeContentQualityRuleTest < Minitest::Test
  def test_reports_missing_image_alt_across_the_whole_page
    issues = Crawlscope::IssueCollection.new
    page = page_with(
      main: '<picture><source srcset="/photo.webp"><img src="/photo.jpg"></picture><img src="/photo.jpg"><img loading="lazy">',
      extra_markup: '<header><img src="/logo.svg"></header><footer><img src="/footer.svg"></footer>'
    )

    Crawlscope::Rules::ContentQuality.new.call(urls: [page.url], pages: [page], issues: issues)

    matches = issues.to_a.select { |issue| issue.code == :missing_image_alt }
    assert_equal 1, matches.size
    issue = matches.first
    assert_equal :warning, issue.severity
    assert_equal :content_quality, issue.category
    assert_equal page.url, issue.url
    assert_equal "images missing alt attributes: 5", issue.message
    assert_equal 5, issue.details[:count]
    assert_equal ["/logo.svg", "/footer.svg", "/photo.jpg"], issue.details[:image_sources]
  end

  def test_allows_present_image_alt_attributes_including_decorative_images
    issues = Crawlscope::IssueCollection.new
    page = page_with(main: '<img src="/photo.jpg" alt="A mountain"><img src="/decoration.svg" alt=""><img src="/empty.svg" alt>')

    Crawlscope::Rules::ContentQuality.new.call(urls: [page.url], pages: [page], issues: issues)

    refute_includes issues.to_a.map(&:code), :missing_image_alt
  end

  def test_does_not_report_missing_image_alt_when_there_are_no_images
    issues = Crawlscope::IssueCollection.new
    page = page_with(main: "Text only")

    Crawlscope::Rules::ContentQuality.new.call(urls: [page.url], pages: [page], issues: issues)

    refute_includes issues.to_a.map(&:code), :missing_image_alt
  end

  def test_skips_non_html_pages
    issues = Crawlscope::IssueCollection.new
    page = Crawlscope::Page.new(
      url: "https://example.com/file", normalized_url: "https://example.com/file",
      final_url: "https://example.com/file", normalized_final_url: "https://example.com/file",
      status: 200, headers: {}, body: "", doc: nil
    )

    Crawlscope::Rules::ContentQuality.new.call(urls: [page.url], pages: [page], issues: issues)

    assert_empty issues.to_a
  end

  def test_reports_thin_visible_text_and_low_html_text_ratio
    issues = Crawlscope::IssueCollection.new
    page = page_with(main: "Short page <div>#{"<span></span>" * 500}</div>")

    Crawlscope::Rules::ContentQuality.new.call(urls: [page.url], pages: [page], issues: issues)

    codes = issues.to_a.map(&:code)
    assert_includes codes, :thin_visible_text
    assert_includes codes, :low_visible_text_ratio
  end

  def test_visible_text_ratio_ignores_markup_outside_main_content
    issues = Crawlscope::IssueCollection.new
    page = page_with(
      main: Array.new(260) { |index| "word#{index}" }.join(" "),
      head_markup: "<style>#{"body{}" * 10_000}</style>",
      extra_markup: "<nav>#{"<a href=\"/\">Navigation</a>" * 500}</nav>"
    )

    Crawlscope::Rules::ContentQuality.new.call(urls: [page.url], pages: [page], issues: issues)

    refute_includes issues.to_a.map(&:code), :low_visible_text_ratio
  end

  def test_visible_text_ratio_ignores_form_payload_markup
    issues = Crawlscope::IssueCollection.new
    page = page_with(
      main: <<~HTML
        <p>#{Array.new(260) { |index| "word#{index}" }.join(" ")}</p>
        <form>
          <div data-select-autocomplete-options-value="#{"x" * 50_000}">
            <input type="text" name="country">
          </div>
        </form>
      HTML
    )

    Crawlscope::Rules::ContentQuality.new.call(urls: [page.url], pages: [page], issues: issues)

    refute_includes issues.to_a.map(&:code), :low_visible_text_ratio
  end

  def test_reports_low_unique_token_ratio_for_repetitive_content
    issues = Crawlscope::IssueCollection.new
    page = page_with(main: ("hotel location service " * 100).strip)

    Crawlscope::Rules::ContentQuality.new.call(urls: [page.url], pages: [page], issues: issues)

    issue = issues.to_a.find { |item| item.code == :low_unique_token_ratio }
    assert issue
    assert_operator issue.details[:ratio], :<, issue.details[:threshold]
  end

  private

  def page_with(main:, extra_markup: "", head_markup: "")
    body = <<~HTML
      <html>
        <head>
          <title>Content quality</title>
          #{head_markup}
        </head>
        <body>
          #{extra_markup}
          <main>#{main}</main>
        </body>
      </html>
    HTML

    Crawlscope::Page.new(
      url: "https://example.com/page",
      normalized_url: "https://example.com/page",
      final_url: "https://example.com/page",
      normalized_final_url: "https://example.com/page",
      status: 200,
      headers: {"content-type" => "text/html"},
      body: body,
      doc: Nokogiri::HTML(body)
    )
  end
end
