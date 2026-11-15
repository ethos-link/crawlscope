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

### Required types by URL

Schema validation checks the markup a page contains. To detect a missing type
even when other valid markup exists, configure a URL policy:

```ruby
Crawlscope.configure do |config|
  config.required_structured_data_types = ->(url) {
    case URI(url).path
    when %r{\A/guides/[^/]+/?\z}
      [["Article", "BlogPosting", "NewsArticle"]]
    when "/guides"
      ["CollectionPage", "ItemList"]
    when %r{/benchmark/?\z}
      ["WebPage", "Dataset"]
    else
      []
    end
  }
end
```

Each string requires that type. A nested array accepts any of its types.
Return an empty array for URLs without a type requirement. The callback receives
the full URL; the host owns the route policy and content classification.

The default sitemap rule and direct URL audits use this policy. A missing
requirement produces `structured_data_missing_required_type` in sitemap
findings and a validation failure in direct audits, including their reports and
exit status. Top-level items, JSON-LD type arrays and `@graph` nodes count;
an article linked inside an ItemList does not satisfy an article-page requirement.
Microdata items also count. Custom rule registries must pass the callback to
`Rules::StructuredData.new(required_types: callback)` themselves.

This checks type presence; the schema registry still validates supported types.
An index, product page or dataset should not acquire Article markup solely
because an external crawler classified its prose as an article.

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
