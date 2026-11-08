# Crawlscope

[![Gem Version](https://badge.fury.io/rb/crawlscope.svg)](https://badge.fury.io/rb/crawlscope)
[![Commit messages](https://github.com/ethos-link/crawlscope/actions/workflows/commitlint.yml/badge.svg)](https://github.com/ethos-link/crawlscope/actions/workflows/commitlint.yml)

`crawlscope` audits sitemap URLs for indexability, metadata, structured data and internal links.

It is built by [Ethos Link](https://www.ethos-link.com) and used in production by [Reviato](https://www.reviato.com).

It is designed for Rails apps and plain Ruby scripts that want:

- sitemap-driven crawling
- structured validation issues instead of free-form strings
- app-configurable rule and schema registries
- first-party rake tasks instead of a large DSL
- optional browser rendering for JavaScript-heavy pages

It works in three modes:

- as a plain Ruby library
- as a standalone CLI
- as Rails rake tasks through the included Railtie

The default rule set includes:

- indexability blockers
- metadata validation
- structured-data validation
- uniqueness checks
- content-quality checks
- internal-link checks

## Documentation

This README and the linked repository guides describe the checked-out code.
The [Ethos Link project page](https://www.ethos-link.com/opensource/crawlscope)
provides the canonical public project guide, overview and resources.

- [Rails integration and tasks](docs/rails.md)
- [Rule catalogue and schema registries](docs/rules.md)
- [Server timing and diagnostic headers](docs/server-timing.md)

## Installation

Crawlscope requires Ruby 4.0 or newer. Rails is optional; the CLI and Ruby
library run without it. Rails integration requires host-installed Rails 8.

Add this line to your application's Gemfile:

```ruby
gem "crawlscope", require: false
```

`require: false` keeps Crawlscope and its crawl stack out of normal Rails web
and job process boot. Require `crawlscope` at the application boundary that
runs an audit, or use the task setup below.

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

`crawlscope` only loads Ferrum when you run in browser mode. Install a compatible Chrome or Chromium executable as well.

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

Set `CRAWLSCOPE_PROFILE_TOKEN` through the process environment or your secret
manager when the site protects diagnostic timing with `X-Profile-Token`.
Crawlscope intentionally has no `--profile-token` flag because command arguments
can be exposed through shell history and process listings.

Validation output is grouped for terminal scanning:

```text
Crawlscope validation
Base URL: https://example.com
Sitemap: https://example.com/sitemap.xml
URLs: 24
Pages: 24
Status: WARNINGS
Issues: 3 total (3 warnings)

Links: Too few incoming links without nofollow (2 warnings)
  - /pricing  incoming links without nofollow: 1; minimum 2
      linked from: /
  - /features  incoming links without nofollow: 1; minimum 2
      linked from: /

Metadata: Missing title (1 warning)
  - /draft  missing <title>
```

Reports include all issues and related URLs. Errors appear before warnings and
notices. Each related URL has a label, such as `linked from`, `links to`, or
`page`. JSON-LD errors appear below the page URL with the type, field, and
constraint. Same-origin URLs use paths; other URLs retain their scheme and host.
For automation in Ruby, use `result.issues` and each issue's `code`, `severity`,
`url`, and `details` rather than matching the report text.

Metadata length limits appear in the group heading; each row shows the measured
length. The default maximums are 160 characters for a meta description and 110
characters for an Article JSON-LD `headline`. These are separate Crawlscope
validation limits for separate fields. Server timing lists pages only when the
reported duration exceeds 50 ms; aggregate statistics include all responses.

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
- `server_timing_summary`: aggregate response timing data when pages publish it

`result.ok?` returns `false` when an error is present. Warnings and notices
remain available through `result.issues` without making the result fail.

## Rails integration

Add `gem "crawlscope", require: false` to the host application's Gemfile, run
`bundle install`, then install the task/configuration integration:

```sh
bin/rails generate crawlscope:install
bin/rails crawlscope:validate
```

Edit the generated `Crawlscope.configure` block to set `base_url`,
`sitemap_path` and any custom rule/schema registries. Tasks load and apply it
automatically. From runtime application code, apply the generated loader and
execute the crawl explicitly:

```ruby
CrawlscopeConfiguration.apply
result = Crawlscope.configuration.audit.call
```

See [Rails integration](docs/rails.md) for lazy loading, all tasks,
environment overrides and structured-data URL audits.

## Configuration and limits

The shared configuration defaults to HTTP rendering, the async fetch executor,
10 concurrent requests and a 20-second request timeout. Browser rendering uses
the threaded executor with at most four concurrent browser fetches. Configure
`concurrency`, `timeout_seconds`, `renderer`, `fetch_executor`, `rule_registry`
and `schema_registry` through `Crawlscope.configure` when using that shared
configuration; direct `Crawlscope::Crawl.new` callers pass their own options.

Use [rule and schema registries](docs/rules.md) to select or extend checks.
Near-duplicate scanning is limited to 250 HTML pages by default; exact duplicate
checks still run for larger crawls. Validation describes observed responses and
configured rules; it does not establish Google rich-result eligibility or
search ranking.

[Server timing](docs/server-timing.md) covers response timings, diagnostic
profile tokens and the limits of those measurements.

## Contributing

1. Fork it
1. Create a branch (`git checkout -b feature/my-feature`)
1. Commit your changes
1. Push (`git push origin feature/my-feature`)
1. Open a Pull Request

Please use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages.

## License

MIT License, see [LICENSE.txt](LICENSE.txt)

## Development and releases

Use published [Ethos Gemkit](https://github.com/ethos-link/ethos-gemkit) for shared
tooling. Keep the exact Gemfile version and workflow commit pins on the same release.

```sh
bundle install
bundle exec lefthook install
bundle exec rake verify
```

Tests use controlled local fixtures and need no service account.
Release preparation, publication, registry setup and recovery are documented
in the [Gemkit release guide](https://github.com/ethos-link/ethos-gemkit#releasing-a-gem).

## About Ethos Link

[Ethos Link](https://www.ethos-link.com) is a software company founded by
[Paulo Fidalgo](https://www.fidalgo.pt). This gem is part of the open-source
tooling we publish alongside our business products:

- [Reviato](https://www.reviato.com): collect private customer feedback and analyse public reviews.
- [Nuntio](https://www.nuntiohq.com): prepare, review and schedule social posts.
- [EthosPlaces](https://www.ethos.place): find places, opening hours and contact details.

Explore our [open-source projects](https://www.ethos-link.com/opensource).
