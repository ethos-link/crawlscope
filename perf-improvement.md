# Crawlscope Performance Improvement Plans

Date: 2026-06-01

## Executive Summary

Crawlscope is already partially parallel: `Crawlscope::Crawler` uses a
`Concurrent::FixedThreadPool` to fetch sitemap URLs, and HTTP connections are
cached per worker thread. The remaining time growth is likely coming from three
places:

1. Sitemap expansion is recursive and sequential.
2. Rule execution is sequential after the crawl completes.
3. The links rule can trigger additional target resolution fetches after the
   main crawl, also through a sequential rule path.

The best next step is not "parallelize everything." The best next step is a
bounded async fetch layer that unifies page fetches, child sitemap fetches, and
link target resolution behind one concurrency budget, while keeping analysis
mostly deterministic and sequential until rules are explicitly classified as
parallel-safe.

Recommendation: implement Plan 1 first, then adopt the safe parts of Plan 2.
Defer Plan 3 until benchmarks prove the graph-level complexity is needed.

## Implementation Update

Plan 1 has been implemented with the deliberate Ruby `>= 3.3` contract change.
The default executor remains threaded, and `fetch_executor: :async` is now
available for HTTP crawls through `async-http-faraday`.

The safe follow-on parallelization work is also implemented:

- child sitemap indexes expand through the bounded fetch executor,
- extra link target fetches are resolved in bounded batches,
- canonical target checks reuse the link target cache,
- link extraction and uniqueness summaries use bounded parallel maps.

Measured outcome: async is production-ready, but async alone is not 2x faster
than the existing threaded executor. The 2x+ improvement comes from applying
bounded parallelism to previously serial phases, especially child sitemap
expansion. See `async-performance-assessment.md` for current benchmark numbers.

## Current Implementation Evidence

- `lib/crawlscope/crawler.rb` delegates URL scheduling to
  `Crawlscope::FetchExecutor`.
- `lib/crawlscope/http.rb` uses Faraday and can run through the async HTTP
  adapter for `fetch_executor: :async`.
- `lib/crawlscope/crawl.rb` currently runs in this order: read sitemap URLs,
  crawl all pages, collect fetch errors, cache pages, then scan rules.
- `lib/crawlscope/crawl.rb` calls each rule sequentially in `scan`.
- `lib/crawlscope/sitemap.rb` recursively expands child sitemaps in sequence.
- `lib/crawlscope/rules/links.rb` groups links and resolves unique internal
  targets through the crawl context, which can batch-fetch uncrawled target
  pages.
- `lib/crawlscope/issue_collection.rb` is a simple collection around an Array,
  suitable for current sequential rule execution but not safe as a shared sink
  for parallel rule writers without synchronization or per-task collections.
- The gemspec currently requires Ruby `>= 3.3.0`.

## Async Ecosystem Notes

Async is now a mature fiber-scheduler stack, not a speculative experiment. Its
current docs describe it as a composable asynchronous I/O framework based on
`io-event`, with lightweight fiber concurrency and multi-thread/process
containers available when actual parallelism is needed.

Relevant current constraints:

- `async` 2.39.0 was released on April 5, 2026 and requires Ruby `>= 3.3`.
- `async-http` 0.95.1 was released on May 6, 2026 and requires Ruby `>= 3.3`.
- `async-http-faraday` 0.22.2 was released on April 10, 2026 and requires Ruby
  `>= 3.3`.
- Current Crawlscope now supports Ruby `>= 3.3.0`, so adding the latest Async
  gems as runtime dependencies is an explicit public compatibility change.

Implication: async work should either:

- bump Crawlscope's Ruby requirement to `>= 3.3` in a planned contract change,
  with `UPGRADE.md` guidance; or
- keep the current threaded Faraday path as the default while exposing async as
  an opt-in executor.

## Plan 1: Bounded Async Fetch Layer

Replace the current fetch executor with a small fetch orchestration abstraction:

- Keep `Crawlscope::Crawler.call(urls)` as the public boundary.
- Add a `FetchExecutor` interface with threaded and async implementations.
- Use the threaded implementation as the default.
- Add an async implementation using `async` and either `async-http` directly or
  `async-http-faraday`.
- Apply one shared concurrency budget to:
  - sitemap URL page fetches,
  - child sitemap fetches,
  - link target resolution fetches.
- Deduplicate normalized URLs before scheduling fetches.
- Preserve deterministic output by sorting returned pages back to input URL
  order, or by sorting by normalized URL before rule analysis.
- Keep rule execution sequential for now.

### Why This Fits The Current Code

The existing code already has a natural page-fetch boundary:
`Crawler.new(page_fetcher:, concurrency:).call(urls)`. The HTTP fetcher already
encapsulates transport details. The crawl context already resolves extra link
targets through one `resolve_target` callable. That means the highest-leverage
change is to make all URL I/O share a smarter scheduler, not to rewrite every
rule.

### Expected Measurable Effect

- Wall-clock time should improve most on I/O-heavy crawls with many URLs,
  redirects, missing pages, or internal links not already in the sitemap.
- CPU-heavy rule time will not improve much.
- Memory usage should stay bounded because one concurrency budget controls all
  network fan-out.
- Determinism can remain high if page ordering and issue ordering are
  normalized before reporting.

### Reductio Ad Absurdum

Assume this plan is pushed to the extreme: every discovered URL and link target
is scheduled immediately with unbounded async tasks. The result is faster only
on a toy site. On a real site it creates too many open sockets, hits rate
limits, destabilizes browser mode, and makes failures look nondeterministic.

Therefore the core of the plan cannot be "async means unlimited." It must be
"async with explicit global and per-host bounds." If that constraint is kept,
the contradiction disappears and the plan remains valid.

### Implementation Steps

1. Add a benchmark fixture with delayed sitemap pages and delayed link targets.
2. Extract current thread-pool logic into `Crawlscope::FetchExecutor::Threaded`.
3. Add a shared URL cache keyed by normalized requested URL and normalized final
   URL.
4. Route `Crawler` and `Crawl#resolve` through the shared executor/cache.
5. Add optional `Crawlscope::FetchExecutor::Async` behind a feature flag or
   renderer/transport setting.
6. Keep issue collection and rule execution unchanged.
7. Document Ruby 3.3 requirements for the async transport and release
   contract.

## Plan 2: Split Crawl And Analyze Pipeline

Turn the current "crawl everything, then analyze everything" flow into a
two-phase pipeline:

- Fetch pages concurrently.
- As each page finishes, run per-page rules immediately:
  - indexability,
  - metadata,
  - structured data,
  - content quality checks that inspect only one page.
- Store per-page issues in page-local collections.
- After all pages finish, run aggregate rules:
  - uniqueness,
  - link graph checks,
  - orphan/internal inlink checks.
- Merge issue collections in deterministic order.

### Why This Fits The Current Code

Several rules already accept the same broad signature:

```ruby
rule.call(urls: urls, pages: pages, issues: issues, context: context)
```

That interface is convenient, but it hides whether a rule is per-page or
aggregate. Splitting rules by capability would let Crawlscope overlap useful
analysis with network wait time while keeping global checks accurate.

### Expected Measurable Effect

- Users get earlier partial results in future streaming/reporting modes.
- Wall-clock time improves when per-page parsing/checking is non-trivial and
  network latency leaves idle CPU time.
- Total runtime may improve less than Plan 1 if most time is still network.
- Implementation risk is moderate because rule contracts need classification.

### Reductio Ad Absurdum

Assume every rule is treated as page-local and run as soon as each page arrives.
Uniqueness becomes wrong because it needs all pages. Link graph checks become
wrong because inbound counts need all resolved links. Orphan-page detection can
report false positives before all links have been seen.

Therefore the plan is only valid if Crawlscope makes rule phase explicit:
`per_page`, `post_crawl`, or `graph`. Without that classification, faster
analysis produces faster wrong answers.

### Implementation Steps

1. Add rule metadata, for example `phase: :per_page` or `phase: :aggregate`.
2. Keep existing rules aggregate by default.
3. Move only obviously local rules into `:per_page` after focused tests.
4. Change `IssueCollection` usage to per-task collections, then merge in stable
   order.
5. Add tests proving aggregate rules still see the complete page set.
6. Add timing instrumentation for crawl, per-page analysis, and aggregate
   analysis.

## Plan 3: Unified Async Crawl Graph

Model the crawl as a bounded async graph rather than a linear crawl:

- Fetch the root sitemap.
- Fetch child sitemaps concurrently.
- Schedule page fetches as URLs are discovered.
- Extract links as pages arrive.
- Schedule uncrawled internal link targets through the same bounded queue.
- Run page-local checks as soon as a page arrives.
- Run graph/global checks after the queue drains.
- Maintain one canonical `PageStore` and `TargetResolutionStore`.

### Why This Fits The Problem

The slowest large crawls are not just "N sitemap URLs." They are closer to a
graph:

- a root sitemap points to child sitemaps,
- pages point to internal targets,
- redirects create final URLs,
- rules need both requested and final URL identity.

A graph executor can remove duplicate work and prevent the current shape where
extra link-target fetches happen later as a second network wave.

### Expected Measurable Effect

- Best theoretical wall-clock reduction for large sites with many child
  sitemaps and link targets.
- Better dedupe because sitemap URLs, final URLs, and link targets share one
  store.
- More complex failure semantics: cancellation, retries, partial graph state,
  and stable issue ordering must be designed up front.

### Reductio Ad Absurdum

Assume the crawl graph eagerly follows every internal link, every redirect, and
every discovered target until no new URL remains. Crawlscope stops being a
sitemap validation tool and becomes a general web crawler. Runtime becomes
unbounded, robots/rate-limit behavior becomes harder to reason about, and the
reported URL set drifts away from the sitemap contract.

Therefore the graph must be constrained by Crawlscope's product boundary:
sitemap URLs are the primary audit set; extra target resolution exists only to
validate links from those pages. The graph executor is valid only if it refuses
to become an unlimited site crawler.

### Implementation Steps

1. Define graph scope formally:
   - audit URLs from sitemap,
   - child sitemap URLs,
   - internal link targets from audited pages,
   - no recursive full-site expansion unless explicitly configured.
2. Add `PageStore` and `ResolutionStore` with stable URL normalization.
3. Add a bounded async work queue with global and per-host limits.
4. Add cancellation and timeout policy at the graph level.
5. Add stable result materialization before calling aggregate rules.
6. Add benchmark coverage for:
   - many child sitemaps,
   - many repeated internal links,
   - redirects,
   - broken targets,
   - slow responses.

## Ratings

Scores are 1-5, where 5 is best.

| Aspect | Plan 1: Bounded Async Fetch Layer | Plan 2: Split Crawl/Analyze | Plan 3: Unified Async Crawl Graph |
| --- | ---: | ---: | ---: |
| Expected wall-clock improvement | 4 | 3 | 5 |
| Time to implement | 4 | 3 | 1 |
| Correctness risk | 4 | 3 | 2 |
| Deterministic reporting | 4 | 3 | 2 |
| Public API stability | 4 | 3 | 2 |
| Ruby 3.3 compatibility path | 4 | 5 | 3 |
| Async ecosystem leverage | 4 | 2 | 5 |
| Memory/socket boundability | 4 | 4 | 3 |
| Testability | 4 | 3 | 2 |
| Observability potential | 4 | 5 | 5 |
| Overall score | 40 | 34 | 30 |

## Recommendation

Implement Plan 1 first.

It attacks the most likely bottleneck, keeps the current public shape intact,
and can be shipped in small steps. It also creates the infrastructure needed by
the other two plans: a shared fetch executor, URL dedupe, timing metrics, and
transport abstraction.

Use this sequence:

1. Add timing instrumentation and benchmark fixtures before changing behavior.
2. Refactor the existing threaded fetcher into an explicit executor.
3. Share the executor/cache between initial sitemap page fetches and link
   target resolution.
4. Add async transport with the deliberate Ruby `>= 3.3` contract change
   documented in `UPGRADE.md`.
5. After the fetch layer is measurable, implement the safe subset of Plan 2:
   classify rules by phase and move only clearly per-page rules into overlapped
   analysis.

Do not start with Plan 3. It is attractive architecturally, but it creates too
many new semantics before we have measurements. The reductio failure mode is
also severe: Crawlscope could quietly become an unbounded crawler instead of a
sitemap-driven validator.

## Metrics To Track

Add these measurements before and after each step:

- total runtime,
- sitemap expansion time,
- audited page fetch time,
- link target resolution time,
- per-rule analysis time,
- total requested URLs,
- unique fetched URLs,
- duplicate suppressed URLs,
- max active fetches,
- max active fetches per host,
- socket/open connection count if available,
- issue count by code,
- output ordering stability across repeated runs.

## Acceptance Criteria

Plan 1 is successful when:

- a delayed-response benchmark shows reduced wall-clock time at the same issue
  count,
- output is stable across repeated runs,
- `CONCURRENCY=1` preserves current sequential semantics,
- `CONCURRENCY=N` never schedules more than N active network fetches globally,
- link target resolution reuses already fetched pages,
- Ruby 3.3+ users have a working threaded default and an opt-in async executor.

## Sources

- Local implementation: `lib/crawlscope/crawler.rb`,
  `lib/crawlscope/crawl.rb`, `lib/crawlscope/http.rb`,
  `lib/crawlscope/sitemap.rb`, `lib/crawlscope/rules/links.rb`,
  `lib/crawlscope/issue_collection.rb`, `crawlscope.gemspec`.
- Async docs: https://socketry.github.io/async/
- Async getting started: https://socketry.github.io/async/guides/getting-started/
- Async scheduler docs:
  https://socketry.github.io/async/source/Async/Scheduler/index.html
- Async::HTTP getting started:
  https://socketry.github.io/async-http/guides/getting-started/index
- Async::HTTP::Faraday getting started:
  https://socketry.github.io/async-http-faraday/guides/getting-started/index.html
- RubyGems async 2.39.0:
  https://rubygems.org/gems/async/versions/2.39.0
- RubyGems async-http 0.95.1:
  https://rubygems.org/gems/async-http
- RubyGems async-http-faraday 0.22.2:
  https://rubygems.org/gems/async-http-faraday/versions/0.22.2
