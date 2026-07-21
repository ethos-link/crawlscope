# frozen_string_literal: true

require "uri"
require "zeitwerk"

module Crawlscope
  class Error < StandardError; end

  class ConfigurationError < Error; end
  class ValidationError < Error; end

  class << self
    attr_reader :loader

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset!
      @configuration = Configuration.new
    end
  end
end

Crawlscope.instance_variable_set(:@loader, Zeitwerk::Loader.for_gem)
Crawlscope.loader.ignore("#{__dir__}/generators")
Crawlscope.loader.ignore("#{__dir__}/tasks")
Crawlscope.loader.ignore("#{__dir__}/crawlscope/railtie.rb")
Crawlscope.loader.ignore("#{__dir__}/crawlscope/tasks.rb")
Crawlscope.loader.setup

require "crawlscope/railtie" if defined?(Rails::Railtie)
