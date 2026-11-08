# frozen_string_literal: true

require_relative "lib/crawlscope/version"

Gem::Specification.new do |spec|
  spec.name = "crawlscope"
  spec.version = Crawlscope::VERSION
  spec.authors = ["Paulo Fidalgo", "Ethos Link"]
  spec.email = ["devel@ethos-link.com"]

  spec.summary = "Audit sitemap URLs for metadata, structured data, uniqueness, and links"
  spec.description = "A small Ruby gem for sitemap-driven SEO validation with structured issues, configurable rules and schema registries, optional browser rendering, and Rails rake task integration."
  spec.homepage = "https://www.ethos-link.com/opensource/crawlscope"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  repo = "https://github.com/ethos-link/crawlscope"
  branch = "main"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => repo,
    "bug_tracker_uri" => "#{repo}/issues",
    "changelog_uri" => "#{repo}/blob/#{branch}/CHANGELOG.md",
    "documentation_uri" => spec.homepage,
    "funding_uri" => "https://www.reviato.com/",
    "github_repo" => "ssh://github.com/ethos-link/crawlscope",
    "allowed_push_host" => "https://rubygems.org",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.chdir(__dir__) do
    (Dir["exe/**/*", "lib/**/*", "test/**/*"] + ["CHANGELOG.md", "LICENSE.txt", "README.md", "UPGRADE.md", "docs/rails.md", "docs/rules.md", "docs/server-timing.md"]).select { |file| File.file?(file) }.uniq.sort
  end
  spec.bindir = "exe"
  spec.executables = ["crawlscope"]
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", ">= 1.3"
  spec.add_dependency "async", ">= 2.0"
  spec.add_dependency "async-http-faraday", ">= 0.22"
  spec.add_dependency "faraday", ">= 2.0"
  spec.add_dependency "faraday-follow_redirects", ">= 0.3"
  spec.add_dependency "json-schema", ">= 5.0"
  spec.add_dependency "nokogiri", ">= 1.16"
  spec.add_dependency "zeitwerk", ">= 2.6"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "webmock", "~> 3.0"
end
