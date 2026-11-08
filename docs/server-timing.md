# Server timing

[README](../README.md) · [Project guide](https://www.ethos-link.com/opensource/crawlscope)

Crawlscope parses the
[`Server-Timing`](https://www.w3.org/TR/server-timing/) response header for both
HTTP and browser-rendered crawls. Each page exposes its parsed header through
`page.server_timing`:

```ruby
page.server_timing.each do |metric|
  puts [metric.name, metric.duration, metric.description].compact.join(": ")
end
```

The validation report adds a `Server Timing` section only when at least one page
publishes the header. It includes:

- header coverage and the number of pages publishing durations
- sample and page counts with average, p50, p95, and maximum per metric
- non-duration signals, including cache status and routing descriptions
- the ten pages with the largest individual metric
- the number of malformed entries ignored during parsing

`dur` values are reported as milliseconds, as recommended by the specification.
Crawlscope does not add durations together because metrics such as `total`,
`app`, and `db` may overlap. A page's worst-offender entry is its largest
individual metric instead.

The current HTTP and browser transports expose response headers, not response
trailers. Metrics published only in a `Server-Timing` trailer are therefore not
available to Crawlscope.

Rails 8 applications can enable `ActionDispatch::ServerTiming` with:

```ruby
config.server_timing = true
```

Applications that expose timing only to authenticated diagnostics can set
`config.profile_token`. When this value is present, Crawlscope sends it as
`X-Profile-Token` on same-origin sitemap, HTTP, and browser document requests.
The header survives same-origin redirects but is removed before a cross-origin
redirect, and browser subresources never receive it. Keep the token in the host
application's secret store rather than a URL, command argument, report, or
checked-in configuration.

`CRAWLSCOPE_PROFILE_TOKEN` is the portable default for Rails, the standalone
CLI, Rake tasks, and plain Ruby callers. Rails applications may instead assign
`config.profile_token` from encrypted credentials when that is their established
secret-management boundary; explicit configuration takes precedence over the
environment.

New Rails applications enable Server-Timing in development by default;
production remains opt-in. Rails publishes the Active Support notification names observed during
each request and sums repeated events with the same name. The exact metrics
therefore depend on the application and request, but commonly include controller,
view, database, and cache instrumentation. Crawlscope accepts Rails' dotted
metric names and reports each metric independently.
