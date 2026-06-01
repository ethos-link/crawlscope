namespace :crawlscope do
  desc "Validate URLs with all default Crawlscope rules. Args: [url,sitemap,rules]. ENV: URL, SITEMAP, RULES, JS=1, TIMEOUT, NETWORK_IDLE_TIMEOUT, CONCURRENCY, FETCH_EXECUTOR"
  task :validate, [:url, :sitemap, :rules] => :environment do |_task, args|
    Crawlscope::RakeTasks.validate(url: args[:url], sitemap_path: args[:sitemap], rule_names: args[:rules])
  end

  namespace :validate do
    desc "Directly validate JSON-LD on one URL. Args: [url]. ENV: URL (semicolon-separated), DEBUG=1, JS=1, TIMEOUT, NETWORK_IDLE_TIMEOUT, REPORT_PATH, SUMMARY=1"
    task :ldjson, [:url] => :environment do |_task, args|
      Crawlscope::RakeTasks.ldjson(urls: args[:url])
    end

    desc "Validate URLs with the indexability rule. Args: [url,sitemap]. ENV: URL, SITEMAP, JS=1"
    task :indexability, [:url, :sitemap] => :environment do |_task, args|
      Crawlscope::RakeTasks.validate_rule("indexability", url: args[:url], sitemap_path: args[:sitemap])
    end

    desc "Validate URLs with the metadata rule. Args: [url,sitemap]. ENV: URL, SITEMAP, JS=1"
    task :metadata, [:url, :sitemap] => :environment do |_task, args|
      Crawlscope::RakeTasks.validate_rule("metadata", url: args[:url], sitemap_path: args[:sitemap])
    end

    desc "Validate sitemap URLs with the structured_data rule. Args: [url,sitemap]. ENV: URL, SITEMAP, JS=1"
    task :structured_data, [:url, :sitemap] => :environment do |_task, args|
      Crawlscope::RakeTasks.validate_rule("structured_data", url: args[:url], sitemap_path: args[:sitemap])
    end

    desc "Validate URLs with the uniqueness rule. Args: [url,sitemap]. ENV: URL, SITEMAP, JS=1"
    task :uniqueness, [:url, :sitemap] => :environment do |_task, args|
      Crawlscope::RakeTasks.validate_rule("uniqueness", url: args[:url], sitemap_path: args[:sitemap])
    end

    desc "Validate URLs with the content_quality rule. Args: [url,sitemap]. ENV: URL, SITEMAP, JS=1"
    task :content_quality, [:url, :sitemap] => :environment do |_task, args|
      Crawlscope::RakeTasks.validate_rule("content_quality", url: args[:url], sitemap_path: args[:sitemap])
    end

    desc "Validate URLs with the links rule. Args: [url,sitemap]. ENV: URL, SITEMAP, JS=1"
    task :links, [:url, :sitemap] => :environment do |_task, args|
      Crawlscope::RakeTasks.validate_rule("links", url: args[:url], sitemap_path: args[:sitemap])
    end
  end
end
