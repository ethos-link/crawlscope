# Crawlscope

Audit sitemap URLs for metadata, JSON-LD, indexability and internal links.

For developers checking published sites from Ruby, a command line or Rails tasks. Findings reflect the pages fetched during the crawl. JSON-LD validation does not establish Google rich-result eligibility or search ranking.

[Project and full documentation](https://www.ethos-link.com/opensource/crawlscope) · [RubyGems](https://rubygems.org/gems/crawlscope) · [Changelog](CHANGELOG.md)

## Requirements

Ruby 4.0 or newer. Rails 8 is optional and must be installed by the host application. Browser rendering additionally needs Ferrum and a compatible Chrome or Chromium installation.

## Installation

```sh
gem install crawlscope
```

## Quick start

```sh
gem install crawlscope
crawlscope validate --url https://example.com
```

Replace `https://example.com` with a site you intend to audit. Crawlscope reads `/sitemap.xml`, fetches its pages and prints grouped findings. Errors return a failing status; warnings and notices do not fail `result.ok?`.

See the [full documentation](https://www.ethos-link.com/opensource/crawlscope) for configuration, workflows, operational details and limitations.
For existing installations, read [UPGRADE.md](UPGRADE.md).

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
in the [Gemkit release guide](https://www.ethos-link.com/opensource/ethos-gemkit#releasing-a-gem).

## About Ethos Link

[Ethos Link](https://www.ethos-link.com) is a software company founded by
[Paulo Fidalgo](https://www.fidalgo.pt). We publish these Ruby tools alongside
our business products:

- [Reviato](https://www.reviato.com): private customer feedback and public review analysis.
- [Nuntio](https://www.nuntiohq.com): prepare, review and schedule social posts.
- [EthosPlaces](https://www.ethos.place): find places, opening hours and contact details.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
