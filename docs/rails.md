# Rails integration

[README](../README.md) · [Project guide](https://www.ethos-link.com/opensource/crawlscope)

Install Rails 8 in the host application; Crawlscope does not install Railties.
For a process that loads Crawlscope before Rails, require `crawlscope/rails`
after Rails is available. The Ruby and CLI entry points remain independent of Rails.

Run the install generator after adding the gem:

```bash
bin/rails generate crawlscope:install
```

The generator creates `config/initializers/crawlscope.rb` with an idempotent
`CrawlscopeConfiguration.apply` loader and adds conditional `crawlscope/tasks`
loading to the application's `Rakefile`. This preserves `bin/rails --tasks` and
the `crawlscope:*` tasks without loading Crawlscope during normal Rails boot.

Customize the `Crawlscope.configure` block inside the generated initializer:

```ruby
Crawlscope.configure do |config|
  config.base_url = -> { ENV.fetch("CRAWLSCOPE_BASE_URL", "http://localhost:3000") }
  config.sitemap_path = lambda {
    ENV.fetch("SITEMAP", "#{config.base_url.to_s.chomp("/")}/sitemap.xml")
  }
  config.site_name = ENV.fetch("CRAWLSCOPE_SITE_NAME", "Application")
end
```

Runtime callers must apply the generated configuration before using
Crawlscope:

```ruby
CrawlscopeConfiguration.apply
Crawlscope.configuration.audit.call
```

Rake tasks apply it automatically because `crawlscope/tasks` loads the gem
before Rails evaluates the initializer. Each Rake entry point passes the shared
`Crawlscope.configuration` object to the CLI, so configured base URLs, sitemap
paths, registries, and runtime settings are preserved unless a task argument or
environment override replaces them.

Then run:

```bash
bin/rails crawlscope:validate
```

Available environment overrides:

- `URL`
- `SITEMAP`
- `CRAWLSCOPE_PROFILE_TOKEN`
- `RULES=metadata,links`
- `JS=1` or `RENDERER=browser`
- `TIMEOUT=30`
- `NETWORK_IDLE_TIMEOUT=10`
- `CONCURRENCY=5`
- `FETCH_EXECUTOR=threaded` or `FETCH_EXECUTOR=async`

Available tasks:

```bash
bin/rails crawlscope:validate
bin/rails crawlscope:validate:indexability
bin/rails crawlscope:validate:metadata
bin/rails crawlscope:validate:structured_data
bin/rails crawlscope:validate:uniqueness
bin/rails crawlscope:validate:content_quality
bin/rails crawlscope:validate:links
bin/rails crawlscope:validate:ldjson
```

The same validation surface is also available in the gem repository itself through plain `rake`:

```bash
bundle exec rake crawlscope:validate URL=https://example.com
bundle exec rake 'crawlscope:validate[https://example.com]'
bundle exec rake crawlscope:validate:metadata URL=https://example.com
bundle exec rake 'crawlscope:validate:metadata[https://example.com]'
bundle exec rake crawlscope:validate:ldjson URL=https://example.com/article
bundle exec rake 'crawlscope:validate:ldjson[https://example.com/article]'
```

`crawlscope:validate` runs all default sitemap rules: indexability, metadata,
structured data, uniqueness, content quality, and links. `URL` is the site
base. Without `SITEMAP`, Crawlscope uses the configured sitemap URL, then fetches
`/sitemap.xml` from `URL` over HTTP. With `SITEMAP`, Crawlscope uses `URL` as
the site base and validates URLs from that sitemap. `SITEMAP` may be a full URL
or an explicitly selected local file path.

Plain `rake` does not pass `--url` style flags to tasks. Use `URL=...` or the
task-argument form above instead.

`FETCH_EXECUTOR=async` is the default for HTTP crawling. It uses Ruby's fiber
scheduler and Async::HTTP through Faraday, preserving the same `CONCURRENCY`
bound. Use `FETCH_EXECUTOR=threaded` or `--fetch-executor threaded` for the
thread-pool executor. Browser rendering uses the threaded executor by default
because async fetch execution is only supported with HTTP rendering.

`crawlscope:validate:ldjson` is separate because it directly checks the URL or semicolon-separated URLs in `URL`; it does not crawl the sitemap. Without `URL`, it checks the configured base URL, falling back to `http://localhost:3000`.

## Structured Data URL Audit

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
