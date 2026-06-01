# Upgrade Guide

Use this file for host-app migration notes when a release changes public
contracts, required setup, component locals, generated assets, or runtime
behavior.

## Next Release

### Ruby 3.3 is now required

Crawlscope now depends on the current Async runtime for production async HTTP
fetching. Host applications must run Ruby 3.3 or newer before upgrading.

Recommended migration:

1. Upgrade the host application runtime to Ruby 3.3 or newer.
2. Run `bundle update crawlscope async async-http async-http-faraday`.
3. Keep the default `FETCH_EXECUTOR=threaded` for the first deploy if you want
   a conservative rollout.
4. Enable async fetching with `FETCH_EXECUTOR=async` or
   `--fetch-executor async` after the app is running on the new Ruby version.
