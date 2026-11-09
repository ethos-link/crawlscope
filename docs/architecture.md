# Architecture

Crawlscope separates fetching, document interpretation, audit policy, and
presentation. Public entry points remain small coordinators. The directories
below contain the collaborators they use:

```text
lib/crawlscope/
  crawling/
    fetcher_factory.rb     HTTP/browser construction and browser load errors
    target_resolver.rb     URL normalization, page reuse, and target caching
    target.rb              Resolved target status and indexability
  documents/
    canonical.rb           Canonical href extraction and URL resolution
    robots.rb              Shared robots directive interpretation
  reporting/
    issue_presenter.rb     Issue headings, rows, evidence, and measurements
    url_formatter.rb       URL display that preserves origin and query identity
  rules/
    links.rb               Public links rule; assembles one invocation
    links/
      extractor.rb         Internal anchor extraction
      scope.rb             Shared link inclusion policy
      target_lookup.rb     Per-invocation target lookup and batch resolution
      resolution_check.rb  Broken and redirected link checks
      graph.rb             Inbound counts and source URLs
      inbound_checks.rb    Incoming-link policies
      outgoing_checks.rb   Outgoing-link and discovered sitemap policies
      canonical_checks.rb  Canonical target status and inbound-link policies
      url_checks.rb        URL hygiene
  structured_data/
    document.rb            JSON-LD and microdata extraction
    validator.rb           Shared parse, type-presence, and schema validation
    entry.rb               Per-URL outcome and failure classification
    outcome.rb             Overall success derived from entries
    audit.rb               Fetches direct URLs and adapts validation findings
    report.rb              Summary selection and JSON serialization
```

`Configuration` selects rules and runtime settings. `Run` invokes an audit and
its reporter. `Crawl` coordinates sitemap expansion, fetching, response checks,
and rule execution; `Crawling::TargetResolver` supplies rules with cached target
resolution through the existing `Context` protocol.

The links rule creates its collaborators for each call. A reused rule instance
does not retain a previous crawl's resolver or target cache. `Graph` indexes
resolved incoming links once, excludes self-links and noindex targets, and
retains full URL identity. Inbound and canonical checks ask the same graph for
counts instead of maintaining separate counting algorithms. Path inclusion
policy lives in `Scope`.

Both structured-data entry points use `StructuredData::Validator`. It returns
items and findings without writing output or choosing command exit status.
`Rules::StructuredData` translates findings into the sitemap audit's existing
warning issues. `StructuredData::Audit` translates them into direct-URL entries.
Host path requirements belong in explicit rule configuration.

`StructuredData::Entry` owns failure classification: fetch failure, missing
markup, validation failure, or success. `Outcome#ok?` and summary categories use
that classification. The legacy `Audit::Page` and `Audit::Outcome` constants are
aliases, preserving their constructors and fields.

`Reporter` owns text layout and ordering; `Reporting::IssuePresenter` formats
one issue without performing I/O. `Reporting::UrlFormatter` is shared by crawl
and timing reports. Structured-data errors use the same `ErrorFormatter` in
both audit reports. Existing `Issue#message` values remain available to API
consumers; presenters use structured evidence for richer text rows.

When adding a check, put document interpretation in a shared document object,
policy in a rule, and text formatting in a presenter. Keep network access behind
the fetcher and resolver interfaces. Add behavior tests at the public rule or
command boundary; use direct collaborator tests for policies that need their
own examples. Run `bundle exec rake verify` before handing off changes.
