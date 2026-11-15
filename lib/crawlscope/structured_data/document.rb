# frozen_string_literal: true

require "json"
require "nokogiri"

module Crawlscope
  module StructuredData
    class Document
      Item = Data.define(:source, :data) do
        def types
          nodes = [data]
          types = []
          until nodes.empty?
            node = nodes.pop
            next unless node.is_a?(Hash)

            types.concat(Array(node["@type"]))
            nodes.concat(Array(node["@graph"]))
          end
          types
        end
      end

      def initialize(html:)
        @doc = Nokogiri::HTML(html.to_s)
      end

      def items
        @items ||= extract_json_ld_items + extract_microdata_items
      end

      def json_ld_items
        items.filter_map do |item|
          next unless item.source == "json-ld"
          next unless item.data.is_a?(Hash)
          next if item.data.key?(:error)

          item.data
        end
      end

      private

      def extract_json_ld_items
        @doc.css('script[type="application/ld+json"]').flat_map do |node|
          parse_json_ld(node.content)
        end
      end

      def parse_json_ld(content)
        payload = JSON.parse(content)
        entries = payload.is_a?(Array) ? payload : [payload]

        entries.filter_map do |entry|
          next unless entry.is_a?(Hash)

          Item.new(source: "json-ld", data: entry)
        end
      rescue JSON::ParserError => error
        [Item.new(source: "json-ld", data: {error: "Invalid JSON-LD", message: error.message})]
      end

      def extract_microdata_items
        @doc.css("[itemtype]").filter_map do |node|
          type = node["itemtype"].to_s
          next unless type.start_with?("http://schema.org", "https://schema.org")

          item = extract_microdata_item(node)
          item["@type"] = type.sub(%r{.*/}, "")
          Item.new(source: "microdata", data: item)
        end
      end

      def extract_microdata_item(node)
        item = {}

        node.css("[itemprop]").each do |prop_node|
          prop = prop_node["itemprop"]
          value = extract_microdata_value(prop_node)
          item[prop] = value
        end

        node.css("[itemtype]").select { |entry| entry["itemprop"].nil? }.each do |nested|
          type = nested["itemtype"].to_s.sub(%r{.*/}, "")
          nested_item = extract_microdata_item(nested)
          nested_item["@type"] = type
          item[type] ||= []
          item[type] << nested_item
        end

        item
      end

      def extract_microdata_value(node)
        return if node["itemprop"].nil?
        return node["content"] if node["content"]
        return node["datetime"] if node["datetime"]
        return node["href"] || node["src"] if node["href"] || node["src"]
        return node["value"] if node["value"]
        return node["content"] if node.name == "meta"

        node.text.strip.empty? ? nil : node.text.strip
      end
    end
  end
end
