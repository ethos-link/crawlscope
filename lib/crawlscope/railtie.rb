# frozen_string_literal: true

module Crawlscope
  class Railtie < Rails::Railtie
    rake_tasks do
      require "crawlscope/tasks"
    end
  end
end
