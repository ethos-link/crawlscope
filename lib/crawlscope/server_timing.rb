# frozen_string_literal: true

module Crawlscope
  class ServerTiming
    include Enumerable

    TOKEN = /\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z/
    NUMBER = /\A-?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][+-]?\d+)?\z/
    QUOTED_STRING = /\A"(?:[^"\\\x00-\x1F]|\\[\t\x20-\x7E])*"\z/
    EMPTY_LIST_MEMBER = /\A[ \t]*\z/

    Metric = Data.define(:name, :duration, :description) do
      def timed?
        !duration.nil?
      end
    end

    attr_reader :invalid_count

    def initialize(header)
      @header = header
      @invalid_count = 0
      @metrics = parse.freeze
    end

    def each(&block)
      @metrics.each(&block)
    end

    def empty?
      @metrics.empty?
    end

    def present?
      !@header.nil?
    end

    def size
      @metrics.size
    end

    private

    def parse
      Array(@header).flatten.compact.flat_map do |header|
        metrics_from(header.to_s)
      end
    end

    def metrics_from(header)
      fields, complete = split(header, ",")

      unless complete
        @invalid_count += 1
        fields.pop
      end

      fields.filter_map do |field|
        metric_from(field) unless EMPTY_LIST_MEMBER.match?(field)
      end
    end

    def metric_from(field)
      parts, complete = split(field, ";")
      name = parts.shift.to_s.strip

      if complete && TOKEN.match?(name)
        metric(name, parameters_from(parts))
      else
        @invalid_count += 1
        nil
      end
    end

    def parameters_from(parts)
      parts.each_with_object({}) do |part, parameters|
        name, value = part.strip.split("=", 2)
        next unless name

        name = name.downcase
        next if parameters.key?(name)

        parameters[name] = parameter_value(value.to_s.strip)
      end
    end

    def parameter_value(value)
      if TOKEN.match?(value)
        value
      elsif QUOTED_STRING.match?(value)
        value[1...-1].gsub(/\\(.)/m, '\1')
      end
    end

    def metric(name, parameters)
      duration = duration_from(parameters["dur"])

      if (parameters.key?("dur") && duration.nil?) ||
          (parameters.key?("desc") && parameters["desc"].nil?)
        @invalid_count += 1
        nil
      else
        Metric.new(
          name: name,
          duration: duration,
          description: parameters["desc"]
        )
      end
    end

    def duration_from(value)
      if value && NUMBER.match?(value)
        duration = Float(value)
        duration if duration.finite?
      end
    end

    def split(value, delimiter)
      fields, quoted, escaped = [+""], false, false

      value.each_char do |character|
        if escaped
          escaped = false
        elsif quoted && character == "\\"
          escaped = true
        elsif character == "\""
          quoted = !quoted
        elsif character == delimiter && !quoted
          fields << +""
        end

        fields.last << character unless character == delimiter && !quoted
      end

      [fields, !quoted && !escaped]
    end
  end
end
