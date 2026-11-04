# frozen_string_literal: true

require "rails"
require "rails/railtie"

unless Gem::Requirement.new(">= 8.0", "< 9").satisfied_by?(Gem.loaded_specs.fetch("railties").version)
  raise LoadError, "crawlscope integration requires Rails 8.0 or newer within Rails 8"
end

module Crawlscope
  class Railtie < Rails::Railtie
    rake_tasks do
      require "crawlscope/tasks"
    end
  end
end
