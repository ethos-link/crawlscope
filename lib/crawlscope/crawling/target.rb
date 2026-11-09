# frozen_string_literal: true

module Crawlscope
  module Crawling
    Target = Data.define(:target_url, :resolution) do
      def allowed?(statuses)
        statuses.include?(status)
      end

      def final_path
        Url.path(final_url)
      end

      def final_url
        value = resolution[:final_url].to_s
        value.empty? ? target_url : value
      end

      def ignored_error?
        resolution && status.nil? && resolution[:crawled] && resolution[:error]
      end

      def html?
        resolution && resolution[:html]
      end

      def noindex?
        Documents::Robots.noindex_header?(resolution[:headers] || {}) ||
          Documents::Robots.noindex_meta?(resolution[:doc])
      end

      def status
        resolution && resolution[:status]
      end

      def redirect?
        (status && (300..399).cover?(status.to_i)) || final_url != target_url
      end

      def unresolved?
        resolution.nil? || (status.nil? && !ignored_error?)
      end
    end
  end
end
