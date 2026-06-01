# frozen_string_literal: true

module Crawlscope
  Context = Data.define(:allowed_statuses, :base_url, :concurrency, :fetch_executor, :resolve_target, :resolve_targets, :schema_registry) do
    def fetch(name)
      public_send(name)
    end
  end
end
