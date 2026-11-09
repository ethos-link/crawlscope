# frozen_string_literal: true

module Crawlscope
  module Rules
    class Links
      class Scope
        def crawlable_source_path?(path)
          !path.nil? && INTERNAL_PATH_PREFIXES_TO_SKIP.none? { |prefix| path.start_with?(prefix) }
        end

        def skip_internal_path?(path)
          return true if path == "/"

          INTERNAL_PATH_PREFIXES_TO_SKIP.any? { |prefix| path.start_with?(prefix) }
        end

        def crawlable_path?(path)
          !path.nil? && !skip_internal_path?(path)
        end
      end
    end
  end
end
