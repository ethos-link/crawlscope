# frozen_string_literal: true

module Crawlscope
  module StructuredData
    Outcome = Data.define(:entries) do
      def ok?
        entries.all?(&:ok?)
      end
    end
  end
end
