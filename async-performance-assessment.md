# Async Performance Assessment

Date: 2026-06-01

## Conclusion

Async HTTP is not at least 2x faster than Crawlscope's existing threaded fetch
baseline at the same concurrency.

It is much faster than sequential fetching, but Crawlscope was already parallel
before this work. The meaningful comparison is therefore:

- `fetch_executor: :threaded`, `CONCURRENCY=N`
- `fetch_executor: :async`, `CONCURRENCY=N`

On that comparison, async is roughly 1.01x to 1.11x faster in most local
delayed-response scenarios, with one Ruby 3.4.8 short-delay/high-concurrency
case reaching 1.35x. It does not reach 2x.

The additional production work did produce a 2x+ improvement in a different
place: child sitemap expansion now uses the bounded fetch executor instead of
walking sitemap indexes serially. In the local delayed sitemap benchmark,
bounded expansion is about 7.4x to 7.6x faster than sequential expansion on
Ruby 3.4.8 and Ruby 4.0.3.

## Benchmark Setup

Benchmarks use a local delayed HTTP server and full `Crawlscope::Crawl` runs,
not isolated HTTP calls.

Measured scenarios:

- direct sitemap pages,
- uncrawled internal link targets resolved by the links rule,
- 48 delayed pages or targets,
- 20ms and 80ms response delays,
- concurrency 8 and 16,
- median of 3 runs per executor.

Scripts:

- `test/performance/async_fetch_benchmark.rb`
- `test/performance/fetch_executor_matrix.rb`
- `test/performance/sitemap_expansion_benchmark.rb`

## Results

### Ruby 4.0.3

| Scenario | Threaded | Async | Async vs Threaded |
| --- | ---: | ---: | ---: |
| direct pages, 20ms, c8 | 0.159s | 0.147s | 1.08x |
| direct pages, 20ms, c16 | 0.092s | 0.088s | 1.04x |
| direct pages, 80ms, c8 | 0.528s | 0.521s | 1.01x |
| direct pages, 80ms, c16 | 0.280s | 0.275s | 1.02x |
| link targets, 20ms, c8 | 0.179s | 0.170s | 1.06x |
| link targets, 80ms, c8 | 0.616s | 0.601s | 1.02x |

### Ruby 3.4.8

| Scenario | Threaded | Async | Async vs Threaded |
| --- | ---: | ---: | ---: |
| direct pages, 20ms, c8 | 0.163s | 0.159s | 1.03x |
| direct pages, 20ms, c16 | 0.110s | 0.082s | 1.35x |
| direct pages, 80ms, c8 | 0.524s | 0.518s | 1.01x |
| direct pages, 80ms, c16 | 0.278s | 0.271s | 1.02x |
| link targets, 20ms, c8 | 0.190s | 0.170s | 1.11x |
| link targets, 80ms, c8 | 0.610s | 0.607s | 1.01x |

The earlier simple benchmark also showed the same pattern:

| Runtime | Sequential threaded | Threaded c8 | Async c8 |
| --- | ---: | ---: | ---: |
| Ruby 4.0.3 | 2.141s | 0.284s | 0.305s |
| Ruby 3.4.8 | 2.133s | 0.272s | 0.328s |

### Child Sitemap Expansion

This benchmark measures a sitemap index with eight delayed child sitemaps.
The first row forces a sequential executor by setting concurrency to 1. The
bounded rows use the same crawl path with concurrency 8.

| Runtime | Sequential | Threaded c8 | Async c8 | Best Speedup |
| --- | ---: | ---: | ---: | ---: |
| Ruby 4.0.3 | 2.123s | 0.280s | 0.285s | 7.58x |
| Ruby 3.4.8 | 2.100s | 0.284s | 0.276s | 7.61x |

## Why Async Is Not 2x Faster

The current threaded implementation is already near the latency lower bound.

For 48 pages at 80ms delay and concurrency 16, the theoretical network floor is
roughly:

```text
ceil(48 / 16) * 0.08s = 0.24s
```

Measured results:

- threaded: 0.279s on Ruby 4.0.3
- async: 0.267s on Ruby 4.0.3

That leaves only about 39ms of overhead for threaded execution to eliminate.
Async cannot produce a 2x improvement when the threaded baseline is already
within about 16% of the ideal network floor.

The main reasons:

1. Crawlscope already had bounded parallel fetching through
   `Concurrent::FixedThreadPool`.
2. The benchmark is I/O latency dominated, not CPU or thread scheduling
   dominated.
3. Faraday still adds request/response abstraction overhead in both modes.
4. Local HTTP/1.1 requests do not create a major multiplexing advantage for
   async.
5. The async executor improves resource shape more than wall-clock time when
   the thread pool is already sized correctly.

## What Did Improve

This work still improves the architecture and specific crawl paths:

- async HTTP is now a real transport through `async-http-faraday`,
- fetch executor selection is explicit and documented,
- browser rendering is guarded from async misuse,
- output ordering remains stable,
- uncrawled link targets are resolved as a bounded batch instead of repeatedly
  through the single-target path,
- child sitemap indexes are expanded through the same bounded executor,
- canonical target resolution reuses the link-target cache,
- per-page link extraction and uniqueness summaries can run in bounded parallel
  when the selected executor supports it.

The biggest speed improvement is not async versus threads. It is batching extra
network-bound and per-page rule work through the same bounded executor. In slow
child-sitemap or link-target cases, the batch shape turns what would otherwise
be a serial second wave into roughly `ceil(items / concurrency) * latency`.

## Recommendation

Keep the async implementation, but do not claim a 2x wall-clock speedup over
the current threaded executor.

Position it as:

- production-ready for HTTP crawling,
- useful for fiber-scheduler deployments,
- potentially better at higher concurrency with lower thread pressure,
- equivalent-to-slightly-faster than threaded for the measured local workloads.

If the product goal is a reliable 2x improvement over the previous threaded
baseline, the next performance work should not be "more async." It should
target:

1. persistent fetch/result caching across rule phases,
2. optional higher concurrency with per-host rate limits,
3. streaming per-page analysis so CPU work overlaps network waits,
4. reducing retained response bodies when rules only need parsed document state.

## Decision

Async is production-ready, but it is not a 2x speed feature against the existing
threaded baseline. The production claim should be about scalability and
executor choice. The measured 2x+ speedup comes from applying bounded
parallelism to previously serial crawl phases, especially child sitemap
expansion.
