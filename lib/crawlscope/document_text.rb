# frozen_string_literal: true

module Crawlscope
  module DocumentText
    REMOVED_SELECTORS = "script, style, noscript, template, svg"
    TOKEN_PATTERN = /[[:alnum:]]+/

    module_function

    def body_text(doc)
      text_for(doc, selector: nil)
    end

    def html_for(doc, selector: "main")
      root_for(doc, selector: selector)&.to_html.to_s
    end

    def text_for(doc, selector: "main")
      normalize(root_for(doc, selector: selector)&.text)
    end

    def tokens(text)
      normalize(text).downcase.scan(TOKEN_PATTERN).reject { |token| token.length < 2 }
    end

    def normalize(text)
      text.to_s.gsub(/\s+/, " ").strip
    end

    def root_for(doc, selector:)
      return unless doc

      copy = doc.dup
      copy.css(REMOVED_SELECTORS).remove

      root = selector.to_s.empty? ? nil : copy.at_css(selector)
      root || copy.at_css("body") || copy
    end
  end
end
