# frozen_string_literal: true

require "crawlscope"
require "rake"

unless Rake::Task.task_defined?("crawlscope:validate")
  load File.expand_path("../tasks/crawlscope_tasks.rake", __dir__)
end
