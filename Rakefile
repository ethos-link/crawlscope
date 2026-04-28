# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"
require_relative "lib/crawlscope"
require_relative "lib/crawlscope/version"

VERSION_PATH = File.expand_path("lib/crawlscope/version.rb", __dir__)
VALID_RELEASE_TARGETS = %w[major minor patch].freeze

Rake::TestTask.new(:test) do |task|
  task.libs << "lib"
  task.libs << "test"
  task.test_files = FileList["test/**/*_test.rb"]
  task.warning = false
end

def current_branch
  `git branch --show-current`.strip
end

def clean_worktree?
  system("git diff --quiet") && system("git diff --cached --quiet")
end

def release_version(target)
  target = target.to_s.strip
  raise ArgumentError, "Provide patch, minor, major, or an explicit X.Y.Z version." if target.empty?

  return target if target.match?(/\A\d+\.\d+\.\d+\z/)

  unless VALID_RELEASE_TARGETS.include?(target)
    raise ArgumentError, "Invalid release target #{target.inspect}. Use #{VALID_RELEASE_TARGETS.join(", ")} or X.Y.Z."
  end

  major, minor, patch = Crawlscope::VERSION.split(".").map(&:to_i)

  case target
  when "major"
    "#{major + 1}.0.0"
  when "minor"
    "#{major}.#{minor + 1}.0"
  when "patch"
    "#{major}.#{minor}.#{patch + 1}"
  end
end

def update_version_file(version)
  File.write(
    VERSION_PATH,
    <<~RUBY
      # frozen_string_literal: true

      module Crawlscope
        VERSION = "#{version}"
      end
    RUBY
  )
end

def update_changelog(version)
  success = system("git-cliff", "-c", "cliff.toml", "--unreleased", "--tag", "v#{version}", "-o", "CHANGELOG.md")
  raise "git-cliff failed. Install git-cliff and make sure cliff.toml is valid." unless success
  raise "git-cliff did not update CHANGELOG.md. Ensure there are Conventional Commits since the last tag." if system("git", "diff", "--quiet", "--", "CHANGELOG.md")
end

if Rake::Task.task_defined?("release")
  Rake::Task["release"].clear
end

desc "Publishing is handled by GitHub Actions. Use release:prepare[...] instead."
task :release do
  abort "Use `bundle exec rake 'release:prepare[patch]'` (or minor/major/X.Y.Z). Publishing runs in GitHub Actions after the tag is pushed."
end

namespace :release do
  desc "Prepare a release: update CHANGELOG/version, commit, tag, and push. Accepts patch, minor, major, or X.Y.Z."
  task :prepare, [:target] do |_task, args|
    branch = current_branch
    abort "Release must run on main or master. Current branch: #{branch.inspect}." unless %w[main master].include?(branch)
    abort "Release requires a clean working tree." unless clean_worktree?

    version = release_version(args[:target])
    current = Crawlscope::VERSION
    abort "Release version #{version} is older than current version #{current}." if Gem::Version.new(version) < Gem::Version.new(current)

    update_changelog(version)
    update_version_file(version)

    sh "git add CHANGELOG.md lib/crawlscope/version.rb"
    sh %(git commit -m "chore(release): prepare v#{version}")
    sh %(git tag -a v#{version} -m "Release v#{version}")
    sh "git push origin #{branch}"
    sh "git push origin v#{version}"
  rescue ArgumentError, RuntimeError => e
    abort e.message
  end
end

namespace :crawlscope do
  desc "Validate URLs with all default Crawlscope rules. ENV: URL, SITEMAP, RULES, JS=1, TIMEOUT, NETWORK_IDLE_TIMEOUT, CONCURRENCY"
  task :validate do
    Crawlscope::RakeTasks.validate
  end

  namespace :validate do
    desc "Directly validate JSON-LD on one or more URLs. ENV: URL (semicolon-separated), DEBUG=1, JS=1, TIMEOUT, NETWORK_IDLE_TIMEOUT, REPORT_PATH, SUMMARY=1"
    task :ldjson do
      Crawlscope::RakeTasks.ldjson
    end

    desc "Validate URLs with the metadata rule. ENV: URL, SITEMAP, JS=1"
    task :metadata do
      Crawlscope::RakeTasks.validate_rule("metadata")
    end

    desc "Validate sitemap URLs with the structured_data rule. ENV: URL, SITEMAP, JS=1"
    task :structured_data do
      Crawlscope::RakeTasks.validate_rule("structured_data")
    end

    desc "Validate URLs with the uniqueness rule. ENV: URL, SITEMAP, JS=1"
    task :uniqueness do
      Crawlscope::RakeTasks.validate_rule("uniqueness")
    end

    desc "Validate URLs with the links rule. ENV: URL, SITEMAP, JS=1"
    task :links do
      Crawlscope::RakeTasks.validate_rule("links")
    end
  end
end

task default: %i[test standard]
