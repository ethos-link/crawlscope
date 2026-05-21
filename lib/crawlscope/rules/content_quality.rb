# frozen_string_literal: true

module Crawlscope
  module Rules
    class ContentQuality
      MIN_VISIBLE_TEXT_RATIO = 0.08
      MIN_VISIBLE_WORDS = 250
      MIN_UNIQUE_TOKEN_RATIO = 0.25

      attr_reader :code

      def initialize(
        min_visible_text_ratio: MIN_VISIBLE_TEXT_RATIO,
        min_visible_words: MIN_VISIBLE_WORDS,
        min_unique_token_ratio: MIN_UNIQUE_TOKEN_RATIO
      )
        @code = :content_quality
        @min_visible_text_ratio = min_visible_text_ratio
        @min_visible_words = min_visible_words
        @min_unique_token_ratio = min_unique_token_ratio
      end

      def call(urls:, pages:, issues:, context: nil)
        pages.each do |page|
          next unless page.html?

          validate_visible_words(page, issues)
          validate_visible_text_ratio(page, issues)
          validate_unique_token_ratio(page, issues)
        end
      end

      private

      def validate_unique_token_ratio(page, issues)
        tokens = DocumentText.tokens(DocumentText.text_for(page.doc))
        return if tokens.size < @min_visible_words

        ratio = tokens.uniq.size.to_f / tokens.size
        return if ratio >= @min_unique_token_ratio

        issues.add(
          code: :low_unique_token_ratio,
          severity: :warning,
          category: :content_quality,
          url: page.url,
          message: "visible text has low token variety (#{format_ratio(ratio)})",
          details: {
            ratio: ratio.round(3),
            threshold: @min_unique_token_ratio,
            token_count: tokens.size,
            unique_token_count: tokens.uniq.size
          }
        )
      end

      def validate_visible_text_ratio(page, issues)
        html_bytes = page.body.to_s.bytesize
        return if html_bytes.zero?

        visible_text = DocumentText.body_text(page.doc)
        ratio = visible_text.bytesize.to_f / html_bytes
        return if ratio >= @min_visible_text_ratio

        issues.add(
          code: :low_visible_text_ratio,
          severity: :warning,
          category: :content_quality,
          url: page.url,
          message: "low visible text to HTML ratio (#{format_ratio(ratio)})",
          details: {
            html_bytes: html_bytes,
            ratio: ratio.round(3),
            threshold: @min_visible_text_ratio,
            visible_text_bytes: visible_text.bytesize
          }
        )
      end

      def validate_visible_words(page, issues)
        word_count = DocumentText.tokens(DocumentText.text_for(page.doc)).size
        return if word_count >= @min_visible_words

        issues.add(
          code: :thin_visible_text,
          severity: :warning,
          category: :content_quality,
          url: page.url,
          message: "thin visible text (#{word_count} words)",
          details: {word_count: word_count, minimum: @min_visible_words}
        )
      end

      def format_ratio(value)
        format("%.2f", value)
      end
    end
  end
end
