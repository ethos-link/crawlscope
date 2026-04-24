# Crawlscope

[![Gem Version](https://badge.fury.io/rb/crawlscope.svg)](https://badge.fury.io/rb/crawlscope)
[![Ruby](https://github.com/ethos-link/crawlscope/actions/workflows/ruby.yml/badge.svg)](https://github.com/ethos-link/crawlscope/actions/workflows/ruby.yml)

`crawlscope` is a small Ruby gem for sitemap-driven SEO validation.

It is built by [Ethos Link](https://www.ethos-link.com) and used in production by [Reviato](https://www.reviato.com).

It is designed for Rails apps and plain Ruby scripts that want:

- deterministic sitemap crawling
- structured validation issues instead of free-form strings
- app-configurable rule and schema registries
- first-party rake tasks instead of a large DSL
- optional browser rendering for JavaScript-heavy pages

It works in three modes:

- as a plain Ruby library
- as a standalone CLI
- as Rails rake tasks through the included Railtie

The default rule set includes:

- metadata validation
- structured-data validation
- uniqueness checks
- internal-link checks

## Installation

Add this line to your application's Gemfile:

```ruby
gem "crawlscope"
```

And then execute:

```bash
bundle install
```

Or install it directly:

```bash
gem install crawlscope
```

If you want browser rendering, also add:

```ruby
gem "ferrum"
```

`crawlscope` only loads Ferrum when you run in browser mode.

## CLI Usage

Validate a site from its default sitemap:

```bash
crawlscope validate --url https://example.com
```

Validate only specific rules:

```bash
crawlscope validate --url https://example.com --rules metadata,links
```

Validate structured data on one or more URLs:

```bash
crawlscope ldjson --url https://example.com/article
crawlscope ldjson --url https://example.com/a --url https://example.com/b --summary
```

To use a non-default sitemap, pass `--sitemap`:

```bash
crawlscope validate --url https://example.com --sitemap https://example.com/sitemap.xml
```

Child sitemap indexes are supported automatically.

## Ruby Usage

```ruby
require "crawlscope"

crawl = Crawlscope::Crawl.new(
  base_url: "https://example.com",
  sitemap_path: "https://example.com/sitemap.xml",
  rules: Crawlscope::RuleRegistry.default(site_name: "Example").rules,
  schema_registry: Crawlscope::SchemaRegistry.default
)

result = crawl.call

puts result.ok?
puts result.issues.to_a.map(&:message)
```

## Result Shape

`Crawlscope::Crawl` returns a `Crawlscope::Result` with:

- `urls`: sitemap URLs selected for validation
- `pages`: fetched page snapshots
- `issues`: structured issues with `code`, `severity`, `category`, `url`, and `message`

`result.ok?` returns `false` if any error, warning, or notice is present.

## Rails Usage

In an initializer:

```ruby
Crawlscope.configure do |config|
  config.base_url = -> { "https://example.com" }
  config.sitemap_path = -> { Rails.public_path.join("sitemap.xml").to_s }
  config.site_name = "Example"
  config.schema_registry = -> { Crawlscope::SchemaRegistry.default }
end
```

Then run:

```bash
bin/rails crawlscope:validate
```

Available environment overrides:

- `URL`
- `SITEMAP`
- `RULES=metadata,links`
- `JS=1` or `RENDERER=browser`
- `TIMEOUT=30`
- `NETWORK_IDLE_TIMEOUT=10`
- `CONCURRENCY=5`

Available tasks:

```bash
bin/rails crawlscope:validate
bin/rails crawlscope:validate:metadata
bin/rails crawlscope:validate:structured_data
bin/rails crawlscope:validate:uniqueness
bin/rails crawlscope:validate:links
bin/rails crawlscope:validate:ldjson URL=https://example.com/article
```

The same validation surface is also available in the gem repository itself through plain `rake`:

```bash
bundle exec rake crawlscope:validate URL=https://example.com
bundle exec rake crawlscope:validate:metadata URL=https://example.com
bundle exec rake crawlscope:validate:ldjson URL=https://example.com/article
```

`crawlscope:validate` runs all default sitemap rules: metadata, structured data, uniqueness, and links. `URL` is the site base. Without `SITEMAP`, Crawlscope uses `/sitemap.xml`. With `SITEMAP`, Crawlscope uses `URL` as the site base and validates URLs from that sitemap. `SITEMAP` may be a full URL or a local file path.

`crawlscope:validate:ldjson` is separate because it directly checks the URL or semicolon-separated URLs in `URL`; it does not crawl the sitemap.

### Structured Data URL Audit

For one-off structured-data checks:

```bash
bin/rails crawlscope:validate:ldjson URL=https://example.com/article
bin/rails crawlscope:validate:ldjson URL='https://example.com/a;https://example.com/b' SUMMARY=1
bin/rails crawlscope:validate:ldjson URL=https://example.com/article REPORT_PATH=tmp/structured-data.json
```

Optional flags:

- `DEBUG=1`: print detected items
- `SUMMARY=1`: print grouped failures
- `REPORT_PATH=...`: write a JSON report. Treat this as trusted operator input; Crawlscope writes to the path the task process can access.
- `JS=1` or `RENDERER=browser`: render with Ferrum

## Rules

Built-in rules:

- `metadata`
- `structured_data`
- `uniqueness`
- `links`

### Metadata

Checks:

- missing `<h1>`
- missing `<title>`
- title length
- repeated site name in the title
- missing meta description
- meta description length
- missing canonical link
- canonical mismatch

### Structured Data

Checks:

- malformed JSON-LD
- missing required fields for supported schema types
- schema validation failures from the configured registry
- direct URL structured-data audits through `crawlscope:validate:ldjson`

### Uniqueness

Checks:

- duplicate titles
- duplicate meta descriptions
- duplicate content fingerprints

### Links

Checks:

- broken internal links
- unresolved internal links
- low inbound anchor-link counts

## Schema Registry

`crawlscope` ships with a default schema registry for common types such as:

- `Article`
- `FAQPage`
- `Organization`
- `Product`
- `Review`
- `SoftwareApplication`
- `WebApplication`
- `WebSite`

The default schema definitions live in `Crawlscope::Schemas`; `Crawlscope::SchemaRegistry` owns registration and validation.

Host apps can replace or extend the registry:

```ruby
Crawlscope.configure do |config|
  config.schema_registry = -> { MyApp::StructuredData::SchemaRegistry.new }
end
```

That makes `crawlscope` useful as the audit engine while the app remains the owner of stricter product-specific schema rules.

## Development

```bash
git clone https://github.com/ethos-link/crawlscope.git
cd crawlscope

bundle install
bundle exec rake test
bundle exec rake standard
bundle exec rake
```

### Git hooks

We use [lefthook](https://lefthook.dev/) with the Ruby [commitlint](https://github.com/arandilopez/commitlint) gem to enforce Conventional Commits on every commit. We also use [Standard Ruby](https://standardrb.com/) to keep code style consistent. CI validates commit messages, Standard Ruby, tests, and git-cliff changelog generation on pull requests and pushes to main/master.

Run the hook installer once per clone:

```bash
bundle exec lefthook install
```

### Install locally

```bash
rake install
```

## Release

Releases are tag-driven and published by GitHub Actions to RubyGems. Local release commands never publish directly.

Install [git-cliff](https://git-cliff.org/) locally before preparing a release. The release task regenerates `CHANGELOG.md` from Conventional Commits.

Before preparing a release, make sure you are on `main` or `master` with a clean worktree.

Then run one of:

```bash
bundle exec rake 'release:prepare[patch]'
bundle exec rake 'release:prepare[minor]'
bundle exec rake 'release:prepare[major]'
bundle exec rake 'release:prepare[0.1.0]'
```

The task will:

1. Regenerate `CHANGELOG.md` with `git-cliff`.
1. Update `lib/crawlscope/version.rb`.
1. Commit the release changes.
1. Create and push the `vX.Y.Z` tag.

The `Release` workflow then runs tests, publishes the gem to RubyGems, and creates the GitHub release from the changelog entry.

## Contributing

1. Fork it
1. Create a branch (`git checkout -b feature/my-feature`)
1. Commit your changes
1. Push (`git push origin feature/my-feature`)
1. Open a Pull Request

Please use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages.

## License

MIT License, see [LICENSE.txt](LICENSE.txt)

## About

Made by the team at [Ethos Link](https://www.ethos-link.com) — practical software for growing businesses. We build tools for hospitality operators who need clear workflows, fast onboarding, and real human support.

We also build [Reviato](https://www.reviato.com), “Capture. Interpret. Act.”.
Turn guest feedback into clear next steps for your team. Collect private appraisals, spot patterns across reviews, and act before small issues turn into public ones.
