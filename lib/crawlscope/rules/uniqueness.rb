# frozen_string_literal: true

require "digest"

module Crawlscope
  module Rules
    class Uniqueness
      MINIMUM_SHINGLES = 10
      NEAR_DUPLICATE_THRESHOLD = 0.9
      SHINGLE_SIZE = 5

      attr_reader :code

      def initialize(
        near_duplicate_threshold: NEAR_DUPLICATE_THRESHOLD,
        minimum_shingles: MINIMUM_SHINGLES,
        shingle_size: SHINGLE_SIZE
      )
        @code = :uniqueness
        @minimum_shingles = minimum_shingles
        @near_duplicate_threshold = near_duplicate_threshold
        @shingle_size = shingle_size
      end

      def call(urls:, pages:, issues:, context:)
        page_summaries = pages.filter_map do |page|
          next unless page.html?

          summary_for(page)
        end

        validate_duplicates(page_summaries, issues)
        validate_near_duplicates(page_summaries, issues)
      end

      private

      def content_fingerprint_digest(doc)
        normalized = DocumentText.text_for(doc)
        return if normalized.length < 200

        Digest::SHA256.hexdigest(normalized)
      end

      def duplicates_for(pages, field)
        pages
          .select { |page| !page[field].nil? && !page[field].to_s.empty? }
          .group_by { |page| page[field] }
          .transform_values { |items| items.map { |item| item[:url] } }
          .select { |_value, urls| urls.size > 1 }
      end

      def summary_for(page)
        tokens = DocumentText.tokens(DocumentText.text_for(page.doc))

        {
          content_fingerprint_digest: content_fingerprint_digest(page.doc),
          description: page.doc.at_css('meta[name="description"]')&.[]("content").to_s.strip,
          shingles: shingles_for(tokens),
          title: page.doc.at_css("title")&.text.to_s.strip,
          url: page.url
        }
      end

      def validate_duplicates(page_summaries, issues)
        duplicates_for(page_summaries, :title).each do |value, urls|
          issues.add(
            code: :duplicate_title,
            severity: :warning,
            category: :uniqueness,
            url: nil,
            message: "duplicate title '#{value}' => #{urls.join(", ")}",
            details: {urls: urls, value: value}
          )
        end

        duplicates_for(page_summaries, :description).each do |value, urls|
          issues.add(
            code: :duplicate_meta_description,
            severity: :warning,
            category: :uniqueness,
            url: nil,
            message: "duplicate meta description '#{value}' => #{urls.join(", ")}",
            details: {urls: urls, value: value}
          )
        end

        duplicates_for(page_summaries, :content_fingerprint_digest).each_value do |urls|
          issues.add(
            code: :duplicate_content_fingerprint,
            severity: :warning,
            category: :uniqueness,
            url: nil,
            message: "duplicate page content fingerprint => #{urls.join(", ")}",
            details: {urls: urls}
          )
        end
      end

      def shingles_for(tokens)
        return [] if tokens.size < @shingle_size

        tokens.each_cons(@shingle_size).map { |items| items.join(" ") }.uniq
      end

      def validate_near_duplicates(page_summaries, issues)
        page_summaries.combination(2) do |left, right|
          next if same_content_fingerprint?(left, right)
          next if left[:shingles].size < @minimum_shingles || right[:shingles].size < @minimum_shingles

          similarity = shingle_similarity(left[:shingles], right[:shingles])
          next if similarity < @near_duplicate_threshold

          urls = [left[:url], right[:url]]

          issues.add(
            code: :near_duplicate_content,
            severity: :warning,
            category: :uniqueness,
            url: nil,
            message: "near duplicate page content (#{format("%.2f", similarity)}) => #{urls.join(", ")}",
            details: {similarity: similarity.round(3), threshold: @near_duplicate_threshold, urls: urls}
          )
        end
      end

      def same_content_fingerprint?(left, right)
        !left[:content_fingerprint_digest].nil? &&
          left[:content_fingerprint_digest] == right[:content_fingerprint_digest]
      end

      def shingle_similarity(left, right)
        intersection_size = (left & right).size
        smaller_set_size = [left.size, right.size].min
        return 0.0 if smaller_set_size.zero?

        intersection_size.to_f / smaller_set_size
      end
    end
  end
end
