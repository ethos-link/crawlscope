# Upgrade Guide

Use this file for host-app migration notes when a release changes public
contracts, required setup, component locals, generated assets, or runtime
behavior.

## Next Release

### Structured-data length errors include the measured size

String-length schema errors now include an optional `length` field with the
actual character count. Text reports show the measurement and limit, such as
`Article.headline: 125 characters; maximum 110`. Existing `field`, `issue`, and
`type` fields remain available, and `issue` retains the original validator
message. Applications that enforce exact error-object keys must accept `length`.

### One warning per redirect or canonical mismatch

Sitemap redirects now emit only `sitemap_redirect_url`, rather than also emitting
`redirected_page`. Applications that match `redirected_page` must switch to
`sitemap_redirect_url`; `final_url` and final HTTP `status` remain in details.

Metadata and canonical-target checks skip redirect aliases, so the destination's
canonical is not compared with the redirect's original URL. Metadata checks still
run when the destination is itself in the crawl.

A directly served page with a different canonical emits one warning:
`non_canonical_page_in_sitemap` when it is in the sitemap, or `canonical_mismatch`
otherwise. Applications that previously counted both warnings should handle
either code as one mismatch.

Metadata length reports put the field and limit in the group heading; rows show
only the measured length. Server timing's page list now includes only durations
strictly greater than 50 ms. Aggregate timing statistics still include all
responses, and `result.server_timing_summary` retains all timing data.

### Redirect URLs are excluded from uniqueness checks

Uniqueness checks now compare only HTML pages whose normalized requested and
final URLs match. Redirect aliases no longer produce duplicate-title,
duplicate-description, duplicate-text, or similar-text warnings from the
destination's content. Redirect issues remain in the crawl report. Separate
pages that serve identical content without a redirect are still checked.

No host-app configuration changes are required. Applications that count
uniqueness issues should expect fewer warnings when sitemap URLs redirect.

### Clearer audit messages

Text reports now use plain-language group headings with severity counts and
show errors before warnings and notices. The repeated category summary is
removed. Structured-data errors show the type, field, and constraint on separate
lines (for example, `Article.headline: 125 characters; maximum 110`). Sitemap
redirects show the destination and its final HTTP status once, without the host
for same-origin URLs.
Canonical warnings now identify the canonical target and explain the mismatch.
Link warnings use `linked from` and `links to` to identify each URL's role.
Length and ratio warnings include the limit and units. Reports show every issue
and every related URL on separate lines. Duplicate-title and description values
are shown in full. Link rules retain all source and target URLs rather than
three samples. Missing-sitemap issues keep `source_url` and also provide
`source_urls` with all pages that link to the missing URL. Server timing retains
full descriptions and lists every page whose duration exceeds 50 ms.

Host applications that parse report text or issue messages must update their
matching patterns. Prefer issue codes and structured `details` for automation;
these retain their existing fields, including the original schema errors,
redirect status and final URL, and canonical href. No configuration changes are
required.

The former report limits `Reporter::MAX_ISSUES_PER_GROUP` and
`Rules::Links::MAX_SOURCES_IN_ERROR` are removed. Host applications that reference
these constants must remove those references.

### Default sitemap is fetched over HTTP

Crawlscope no longer prefers `public/sitemap.xml` when validating a localhost
application. Without an explicit `SITEMAP` or configured `sitemap_path`, it now
fetches `/sitemap.xml` from the configured base URL so the crawl observes the
live application and database state.

The Rails installer now generates the same HTTP default. Regenerate or update
existing initializers that use `Rails.public_path.join("sitemap.xml")`.
Explicit local sitemap paths remain supported through `SITEMAP`, `--sitemap`,
or `config.sitemap_path`.

`CRAWLSCOPE_PROFILE_TOKEN` is now the portable default for standalone CLI, Rake,
Rails, and plain Ruby usage. Explicit `config.profile_token` values still take
precedence.

### Server-Timing report output

No host configuration is required. When one or more responses publish a
`Server-Timing` header, the text report now includes an optional `Server Timing`
section. Host applications that parse report text should accept this additional
section.

Parsed metrics are available through `page.server_timing`, and aggregate data is
available through `result.server_timing_summary`. Crawlscope interprets `dur`
values as milliseconds and ignores malformed entries while reporting their
count.

### Ruby 3.3 is now required

Crawlscope now depends on the current Async runtime for production async HTTP
fetching. Host applications must run Ruby 3.3 or newer before upgrading.

Recommended migration:

1. Upgrade the host application runtime to Ruby 3.3 or newer.
2. Run `bundle update crawlscope async async-http async-http-faraday`.
3. Crawlscope now uses `FETCH_EXECUTOR=async` by default for HTTP crawling.
4. Set `FETCH_EXECUTOR=threaded` or pass `--fetch-executor threaded` for a
   conservative rollout or for explicit thread-pool execution.
5. Browser rendering continues to use threaded execution by default because
   async fetch execution is only supported with HTTP rendering.
