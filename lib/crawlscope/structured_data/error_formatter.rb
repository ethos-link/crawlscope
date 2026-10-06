# frozen_string_literal: true

module Crawlscope
  module StructuredData
    class ErrorFormatter
      def self.format(error)
        field = (error[:field] || error["field"]).to_s.sub(/\A#\/?/, "")
        type = error[:type] || error["type"]
        issue = error[:issue] || error["issue"] || "Unknown error"

        if (match = issue.match(/did not contain a required property of '([^']+)'/))
          field = [field, match[1]].reject(&:empty?).join("/")
          message = "is required"
        else
          message = concise_message(issue, error[:length] || error["length"])
        end

        location = [type, field.empty? ? nil : field].compact.join(".")
        "#{location.empty? ? "$" : location}: #{message}"
      end

      def self.concise_message(issue, length)
        if length
          unit = (length == 1) ? "character" : "characters"
          measured_length = "#{length} #{unit}"
        end
        case issue
        when /was not of a maximum string length of (\d+)/
          length ? "#{measured_length}; maximum #{Regexp.last_match(1)}" : "exceeds #{Regexp.last_match(1)} characters"
        when /was not of a minimum string length of (\d+)/
          length ? "#{measured_length}; minimum #{Regexp.last_match(1)}" : "must have at least #{Regexp.last_match(1)} characters"
        when /of type (\w+) did not match the following type: (\w+)/
          "must be #{Regexp.last_match(2)} (got #{Regexp.last_match(1)})"
        else
          issue.sub(/\AThe property '[^']*' /, "")
            .sub(/ in schema [\h-]{36}(?:#\S*)?\z/, "")
        end
      end
      private_class_method :concise_message
    end
  end
end
