# frozen_string_literal: true

require "uri"

module Crawlscope
  class Reporter
    GROUP_LABELS = {
      structured_data_schema_error: "Schema errors",
      structured_data_parse_error: "Parse errors",
      structured_data_missing_type: "Missing @type",
      sitemap_redirect_url: "Redirected URLs",
      non_canonical_page_in_sitemap: "URLs with a different canonical",
      indexable_page_missing_from_sitemap: "Linked pages missing from sitemap",
      sitemap_noindex_url: "URLs that block indexing",
      low_dofollow_inlinks: "Too few incoming links without nofollow",
      low_inbound_anchor_links: "Too few incoming links",
      low_unique_token_ratio: "Repeated words",
      low_visible_text_ratio: "Too little text for the HTML size",
      thin_visible_text: "Too few words",
      orphan_page: "Pages with no incoming links",
      nofollow_internal_outlinks: "Outgoing links with nofollow",
      only_nofollow_internal_inlinks: "Incoming links all use nofollow",
      mixed_follow_internal_inlinks: "Incoming links with and without nofollow",
      http_internal_link: "Links from HTTPS to HTTP",
      canonical_no_internal_inlinks: "Canonical URLs with no incoming links without nofollow",
      canonical_points_to_error: "Canonical URLs that return errors",
      url_double_slash: "Repeated slashes in URL paths",
      multiple_h1: "Multiple <h1> tags",
      multiple_title_tags: "Multiple <title> tags",
      incomplete_open_graph_tags: "Missing Open Graph tags",
      title_too_long: "Title exceeds #{Rules::Metadata::TITLE_MAX_LENGTH} characters",
      meta_description_too_long: "Meta description exceeds #{Rules::Metadata::DESCRIPTION_MAX_LENGTH} characters",
      meta_description_too_short: "Meta description below #{Rules::Metadata::DESCRIPTION_MIN_LENGTH} characters",
      duplicate_content_fingerprint: "Duplicate page text",
      near_duplicate_content: "Similar page text",
      near_duplicate_scan_skipped: "Similar-page check skipped"
    }.freeze

    def initialize(io:)
      @io = io
    end

    def report(result)
      @io.puts("Crawlscope validation")
      @io.puts("Base URL: #{result.base_url}")
      @io.puts("Sitemap: #{result.sitemap_path}")
      @io.puts("URLs: #{result.urls.size}")
      @io.puts("Pages: #{result.pages.size}")

      if result.issues.size.zero?
        @io.puts("Status: OK")
      else
        @io.puts("Status: #{status_for(result.issues)}")
        @io.puts("Issues: #{result.issues.size} total (#{severity_summary(result.issues)})")
      end

      unless result.issues.size.zero?
        @io.puts("")
        report_issue_groups(result.issues, base_url: result.base_url)
      end

      ServerTiming::Reporter.new(io: @io).report(result.server_timing_summary, base_url: result.base_url)
    end

    private

    def status_for(issues)
      grouped = issues.by_severity

      if grouped.key?(:error)
        "FAILED"
      elsif grouped.key?(:warning)
        "WARNINGS"
      else
        "NOTICES"
      end
    end

    def severity_summary(issues)
      severity_summary_for(issues.to_a)
    end

    def report_issue_groups(issues, base_url:)
      grouped = issues.to_a.group_by { |issue| [issue.category, issue.code] }

      grouped
        .sort_by { |(category, code), grouped_issues| [grouped_issues.map { |issue| severity_order(issue.severity) }.min, -grouped_issues.size, category.to_s, code.to_s] }
        .each do |(category, code), grouped_issues|
          label = GROUP_LABELS.fetch(code) { code.to_s.tr("_", " ").capitalize }
          @io.puts("#{category.to_s.tr("_", " ").capitalize}: #{label} (#{severity_summary_for(grouped_issues)})")

          grouped_issues.each do |issue|
            details = issue.details || {}
            if issue.code == :structured_data_schema_error && details[:errors]&.any?
              source = (details[:source] == "json-ld") ? "JSON-LD" : details[:source]
              @io.puts("  - #{relative_url(issue.url, base_url: base_url)}  #{source}")
              details[:errors].each do |error|
                @io.puts("      #{StructuredData::ErrorFormatter.format(error)}")
              end
            else
              @io.puts("  - #{compact_issue(issue, base_url: base_url)}")
              report_related_urls(issue, details, base_url: base_url)
            end
          end

          @io.puts("")
        end
    end

    def severity_order(severity)
      {error: 0, warning: 1, notice: 2}.fetch(severity, 3)
    end

    def severity_summary_for(issues)
      issues.group_by(&:severity).sort_by { |severity, _| severity_order(severity) }
        .map { |severity, entries| "#{entries.size} #{pluralize(severity, entries.size)}" }.join(", ")
    end

    def compact_issue(issue, base_url:)
      parts = []
      parts << relative_url(issue.url, base_url: base_url) if issue.url

      detail = compact_detail(issue, base_url: base_url)
      parts << detail unless detail.empty?

      parts.compact.join("  ")
    end

    def compact_detail(issue, base_url:)
      details = issue.details || {}
      case issue.code
      when :redirected_page, :sitemap_redirect_url, :internal_link_redirects
        if details[:final_url]
          prefix = (issue.code == :sitemap_redirect_url) ? "sitemap URL redirects to" : "redirects to"
          status = details[:status] ? " (final HTTP #{details[:status]})" : ""
          return "#{prefix} #{relative_url(details[:final_url], base_url: base_url)}#{status}"
        end
      when :canonical_mismatch, :non_canonical_page_in_sitemap
        if details[:canonical]
          prefix = (issue.code == :non_canonical_page_in_sitemap) ? "sitemap lists this URL, but its canonical points to" : "canonical points to a different URL:"
          return "#{prefix} #{relative_url(details[:canonical], base_url: base_url)}"
        end
      when :unexpected_status
        return "HTTP #{details[:status]}" if details[:status]
      when :title_too_long, :meta_description_too_long, :meta_description_too_short
        return "#{details[:length]} characters" if details[:length]
      when :broken_internal_link
        return "linked URL returns HTTP #{details[:status]}"
      when :unresolved_internal_link
        return ["cannot check linked URL", details[:error]].compact.join(": ")
      when :indexable_page_missing_from_sitemap
        return "linked page is missing from sitemap"
      when :canonical_points_to_redirect
        status = details[:status] ? " (final HTTP #{details[:status]})" : ""
        return "canonical #{relative_url(details[:canonical], base_url: base_url)} redirects to #{relative_url(details[:final_url], base_url: base_url)}#{status}"
      when :canonical_points_to_error
        return "canonical #{relative_url(details[:canonical], base_url: base_url)} returns HTTP #{details[:status]}"
      when :low_dofollow_inlinks, :low_inbound_anchor_links
        count = details[:dofollow_inbound_count] || details[:inbound_count]
        label = (issue.code == :low_dofollow_inlinks) ? "incoming links without nofollow" : "incoming links"
        return "#{label}: #{count}; minimum #{details[:minimum]}"
      when :low_unique_token_ratio, :low_visible_text_ratio
        label = (issue.code == :low_unique_token_ratio) ? "unique words" : "visible text / HTML bytes"
        return "#{label}: #{percentage(details[:ratio])}; minimum #{percentage(details[:threshold])}"
      when :thin_visible_text
        return "visible words: #{details[:word_count]}; minimum #{details[:minimum]}"
      when :mixed_follow_internal_inlinks
        return "incoming links: #{details[:dofollow_inbound_count]} without nofollow, #{details[:nofollow_inbound_count]} with nofollow"
      when :only_nofollow_internal_inlinks
        return "all #{details[:nofollow_inbound_count]} incoming internal links use nofollow"
      when :duplicate_title, :duplicate_meta_description
        label = (issue.code == :duplicate_title) ? "same title" : "same meta description"
        return "#{label}: #{details[:value].to_s.inspect}"
      when :duplicate_content_fingerprint
        return "same page text"
      when :duplicate_pages_without_canonical
        return "same page text; at least one page has no canonical link"
      when :near_duplicate_content
        return "text similarity: #{percentage(details[:similarity])}; threshold #{percentage(details[:threshold])}"
      when :near_duplicate_scan_skipped
        return "similar-page check skipped: #{details[:page_count]} pages; limit #{details[:max_pages]}"
      when :structured_data_missing_type
        return "#{issue.message} at #{Array(details[:paths]).join(", ")}" if details[:paths]&.any?
      when :noindex_meta, :nofollow_meta, :noindex_follow_meta, :noindex_nofollow_meta,
          :noindex_header, :nofollow_header, :noindex_follow_header, :noindex_nofollow_header,
          :sitemap_noindex_url
        if details[:content]
          source = details[:name] || details[:source]
          label = source ? "#{source}: " : ""
          return "#{issue.message} (#{label}#{details[:content]})"
        end
      end
      issue.message
    end

    def report_related_urls(issue, details, base_url:)
      source_label = (issue.code == :canonical_no_internal_inlinks) ? "canonical on" : "linked from"
      sources = Array(details[:source_urls])
      sources += [details[:source_url]] if details[:source_url]
      relationships = {
        source_label => sources.uniq,
        "links to" => details[:target_urls],
        "page" => details[:urls],
        "linked from (without nofollow)" => details[:dofollow_source_urls],
        "linked from (nofollow)" => details[:nofollow_source_urls]
      }
      relationships.each do |label, urls|
        Array(urls).each do |url|
          @io.puts("      #{label}: #{relative_url(url, base_url: base_url)}")
        end
      end
    end

    def relative_url(url, base_url:)
      return url unless url && base_url

      uri = URI.parse(url)
      base_uri = URI.parse(base_url)

      return url unless uri.host == base_uri.host && uri.scheme == base_uri.scheme && uri.port == base_uri.port

      relative = uri.path.to_s.empty? ? "/" : uri.path
      relative += "?#{uri.query}" if uri.query
      relative += "##{uri.fragment}" if uri.fragment
      relative
    rescue URI::InvalidURIError
      url
    end

    def percentage(value)
      "#{format("%.3f", value * 100).sub(/0+\z/, "").sub(/\.\z/, "")}%"
    end

    def pluralize(word, count)
      return word.to_s if count == 1

      "#{word}s"
    end
  end
end
