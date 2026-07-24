# Upgrade Guide

Use this file for host-app migration notes when a release changes public
contracts, required setup, component locals, generated assets, or runtime
behavior.

## Next Release

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
