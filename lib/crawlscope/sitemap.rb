# frozen_string_literal: true

require "faraday"
require "faraday/follow_redirects"
require "nokogiri"
require "uri"

module Crawlscope
  class Sitemap
    SITEMAP_NAMESPACE = {"xmlns" => "http://www.sitemaps.org/schemas/sitemap/0.9"}.freeze

    def initialize(path:, adapter: nil, concurrency: Configuration::DEFAULT_CONCURRENCY, fetch_executor: Configuration::DEFAULT_FETCH_EXECUTOR, profile_token: nil, timeout_seconds: Configuration::DEFAULT_TIMEOUT_SECONDS)
      @path = path
      @adapter = adapter
      @concurrency = concurrency
      @fetch_executor = fetch_executor
      @profile_token = profile_token
      @timeout_seconds = timeout_seconds
    end

    def urls(base_url:)
      collect_urls(@path, base_url: base_url, visited: Set.new, visited_mutex: Mutex.new).uniq
    end

    private

    def collect_urls(source, base_url:, visited:, visited_mutex:)
      already_visited = visited_mutex.synchronize do
        if visited.include?(source)
          true
        else
          visited.add(source)
          false
        end
      end
      return [] if already_visited

      document = Nokogiri::XML(read(source, base_url: base_url))
      root_name = document.root&.name
      unless %w[sitemapindex urlset].include?(root_name)
        raise ValidationError, "Sitemap #{source} has unexpected root #{root_name.inspect}"
      end

      if root_name == "sitemapindex"
        child_sources = document.xpath("//xmlns:sitemap/xmlns:loc", SITEMAP_NAMESPACE).map do |node|
          resolve_child_source(source, node.text.to_s.strip, base_url: base_url)
        end

        fetch_executor.call(child_sources) do |child_source|
          collect_urls(child_source, base_url: base_url, visited: visited, visited_mutex: visited_mutex)
        end.flatten
      else
        document.xpath("//xmlns:url/xmlns:loc", SITEMAP_NAMESPACE).map do |node|
          Url.normalize_for_base(node.text.to_s.strip, base_url: base_url)
        end
      end
    end

    def read(source, base_url:)
      if Url.remote?(source)
        response = connection.get(source) do |request|
          RequestHeaders.add_profile_token(
            request.headers,
            url: source,
            base_url: base_url,
            profile_token: @profile_token
          )
        end
        unless response.status.to_i.between?(200, 299)
          raise ValidationError, "Sitemap #{source} returned HTTP #{response.status}"
        end

        response.body
      else
        File.read(source)
      end
    end

    def resolve_child_source(parent_source, child_loc, base_url:)
      if Url.remote?(parent_source)
        Url.normalize_for_base(URI.join(parent_source, child_loc).to_s, base_url: base_url)
      elsif (local_child_path = local_child_path(parent_source, child_loc))
        local_child_path
      elsif Url.remote?(child_loc)
        child_loc
      else
        File.expand_path(child_loc, File.dirname(parent_source))
      end
    end

    def local_child_path(parent_source, child_loc)
      basename = File.basename(URI.parse(child_loc).path.to_s)
      return if basename.empty?

      path = File.expand_path(basename, File.dirname(parent_source))
      path if File.file?(path)
    rescue URI::InvalidURIError
      nil
    end

    def connection
      Faraday.new do |faraday|
        faraday.response(
          :follow_redirects,
          limit: Http::MAX_REDIRECTS,
          callback: RequestHeaders.method(:strip_profile_token_on_cross_origin_redirect)
        )
        faraday.options.timeout = @timeout_seconds
        faraday.options.open_timeout = @timeout_seconds
        faraday.adapter @adapter if @adapter
      end
    end

    def fetch_executor
      @fetch_executor_instance ||= FetchExecutor.build(name: @fetch_executor, concurrency: @concurrency)
    end
  end
end
