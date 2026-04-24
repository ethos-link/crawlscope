namespace :crawlscope do
  desc "Validate URLs with all default Crawlscope rules. ENV: URL, SITEMAP, RULES, JS=1, TIMEOUT, NETWORK_IDLE_TIMEOUT, CONCURRENCY"
  task validate: :environment do
    Crawlscope::RakeTasks.validate
  end

  namespace :validate do
    desc "Directly validate JSON-LD on one or more URLs. ENV: URL (required, semicolon-separated), DEBUG=1, JS=1, TIMEOUT, NETWORK_IDLE_TIMEOUT, REPORT_PATH, SUMMARY=1"
    task ldjson: :environment do
      Crawlscope::RakeTasks.ldjson
    end

    desc "Validate URLs with the metadata rule. ENV: URL, SITEMAP, JS=1"
    task metadata: :environment do
      Crawlscope::RakeTasks.validate_rule("metadata")
    end

    desc "Validate sitemap URLs with the structured_data rule. ENV: URL, SITEMAP, JS=1"
    task structured_data: :environment do
      Crawlscope::RakeTasks.validate_rule("structured_data")
    end

    desc "Validate URLs with the uniqueness rule. ENV: URL, SITEMAP, JS=1"
    task uniqueness: :environment do
      Crawlscope::RakeTasks.validate_rule("uniqueness")
    end

    desc "Validate URLs with the links rule. ENV: URL, SITEMAP, JS=1"
    task links: :environment do
      Crawlscope::RakeTasks.validate_rule("links")
    end
  end
end
