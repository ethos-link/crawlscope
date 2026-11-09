# Rules and schemas

[README](../README.md) · [Project guide](https://www.ethos-link.com/opensource/crawlscope)

Built-in rules:

- `indexability`
- `metadata`
- `structured_data`
- `uniqueness`
- `content_quality`
- `links`

## Indexability

Checks:

- page-level meta robots `noindex`
- `X-Robots-Tag: noindex`

## Metadata

Checks:

- missing `<h1>`
- missing `<title>`
- title length
- repeated site name in the title
- missing meta description
- meta description length
- missing canonical link
- canonical mismatch

## Structured Data

Checks:

- malformed JSON-LD
- missing required fields for supported schema types
- schema validation failures from the configured registry
- direct URL structured-data audits through `crawlscope:validate:ldjson`

Sitemap and direct URL audits share the same document validator, including
missing `@type` checks. Direct URL audits treat missing markup as a failure;
sitemap audits retain their warning severity for structured-data findings.

Job detail pages can opt into an exactly-one-JobPosting policy with
`Rules::StructuredData.new(job_posting_path: your_path_pattern)` in a custom
rule registry. No host route patterns are assumed by default. See
[UPGRADE](../UPGRADE.md) for an example registry configuration.

## Uniqueness

Checks:

- duplicate titles
- duplicate meta descriptions
- duplicate content fingerprints
- near-duplicate visible content for up to 250 HTML pages

For larger crawls, exact duplicate checks still run and Crawlscope reports
`near_duplicate_scan_skipped`. Configure `Rules::Uniqueness` with
`max_near_duplicate_pages:` in a custom rule registry to change the limit.

## Content Quality

Checks:

- missing `alt` attributes on `<img>` elements throughout the page, including
  headers and footers (empty `alt=""` is allowed for decorative images)
- thin visible text
- low visible-text-to-HTML ratio
- low unique-token ratio

## Links

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
