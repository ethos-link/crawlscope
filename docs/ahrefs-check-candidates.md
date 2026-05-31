# Ahrefs Issue Crosswalk

This crosswalk compares the Ahrefs issue list against Crawlscope's current
rules and identifies checks that fit the gem's sitemap-driven, internal-audit
scope.

## Current Coverage

- `noindex_meta`, `noindex_header`: covers "Noindex page" via meta robots and
  `X-Robots-Tag`.
- `redirected_page`: covers crawled sitemap URLs that redirect.
- `internal_link_redirects`: covers "Page has links to redirect".
- `low_inbound_anchor_links`: partly covers "Page has only one dofollow
  incoming internal link", but currently does not distinguish dofollow from
  nofollow.
- `title_too_long`: covers "Title too long".
- `meta_description_too_short`, `meta_description_too_long`: covers meta
  description length checks.
- `missing_title`, `missing_meta_description`, `missing_h1`, `multiple_h1`,
  `missing_canonical`, `canonical_mismatch`, and
  `incomplete_open_graph_tags`: covers adjacent metadata checks not present in
  the pasted Ahrefs list.
- `structured_data_parse_error`, `structured_data_schema_error`: covers
  schema.org-style validation errors.
- `missing_structured_data`, `missing_job_posting`, `multiple_job_postings`:
  covers structured-data presence and domain-specific JobPosting rules.
- `duplicate_title`, `duplicate_meta_description`,
  `duplicate_content_fingerprint`, `near_duplicate_content`: covers uniqueness
  checks beyond the pasted Ahrefs list.
- `thin_visible_text`, `low_visible_text_ratio`, `low_unique_token_ratio`:
  covers content-quality checks beyond the pasted Ahrefs list.
- `unexpected_status`, `fetch_failed`, `broken_internal_link`: covers status
  and broken-link checks beyond the pasted Ahrefs list.

## Candidate Checks To Add

### High Fit

1. `nofollow_meta`
   - Ahrefs match: "Nofollow page".
   - Detect `nofollow` in meta robots and `X-Robots-Tag`.
   - This should share parsing with the existing noindex checks so
     `noindex,nofollow`, `none`, and scoped directives are handled consistently.

2. `noindex_follow_meta` / `noindex_follow_header`
   - Ahrefs match: "Noindex follow page".
   - Detect pages that explicitly combine `noindex` with `follow`.
   - This is useful because current Crawlscope reports noindex but does not
     classify whether internal links remain followable.

3. `noindex_nofollow_meta` / `noindex_nofollow_header`
   - Ahrefs match: "Noindex and nofollow page".
   - Detect pages that block indexing and link following.
   - Could also treat `none` as equivalent to `noindex,nofollow`.

4. `canonical_no_internal_inlinks`
   - Ahrefs match: "Canonical URL has no incoming internal links".
   - For each sitemap URL, resolve its canonical target and count internal
     links to the canonical URL/path.
   - This is more precise than `low_inbound_anchor_links`, which counts links
     to the crawled URL/final path rather than canonical target.

5. `nofollow_internal_outlinks`
   - Ahrefs match: "Page has nofollow outgoing internal links".
   - Extend link extraction to retain `rel` attributes and flag internal
     anchors with `rel~="nofollow"`.
   - This also unlocks incoming nofollow/dofollow mix checks.

6. `only_nofollow_internal_inlinks`
   - Ahrefs match: "Page has nofollow incoming internal links only".
   - Count incoming internal links by follow state.
   - Report when a sitemap URL has at least one internal inlink but zero
     dofollow internal inlinks.

7. `mixed_follow_internal_inlinks`
   - Ahrefs match: "Page has nofollow and dofollow incoming internal links".
   - Count incoming internal links by follow state.
   - Report when both counts are positive, with source samples for each class.

8. `low_dofollow_inlinks`
   - Ahrefs match: "Page has only one dofollow incoming internal link".
   - Replace or supplement `low_inbound_anchor_links` with a dofollow-specific
     count.
   - Make the threshold configurable; Ahrefs surfaces "only one", but a host
     app may want `minimum_dofollow_inlinks = 2`.

9. `indexable_page_missing_from_sitemap`
   - Ahrefs match: "Indexable page not in sitemap".
   - Use discovered internal links to find crawlable, indexable HTML pages that
     are not present in the sitemap.
   - This requires Crawlscope to keep discovered internal targets, not only
     sitemap URLs, so it is a larger links/crawl contract change.

10. `sitemap_noindex_url`
    - Ahrefs adjacent documented issue: "Noindex page in sitemap".
    - Current noindex checks run on sitemap pages, but this issue name would
      make the sitemap/indexability conflict explicit.
    - It can be implemented as a second issue emitted from the indexability
      rule, or as a dedicated sitemap consistency rule.

11. `sitemap_redirect_url`
    - Ahrefs match: "3XX redirect" and adjacent "3xx redirect in sitemap".
    - Current `redirected_page` covers this behavior; adding this alias/code
      would make reports match external audit tools more directly.

12. `http_internal_link`
    - Ahrefs adjacent issue: "HTTPS page has internal links to HTTP".
    - Detect internal links from HTTPS pages to HTTP URLs on the same host.
    - This is more actionable than relying on redirect detection after fetch.

13. `canonical_points_to_redirect`
    - Ahrefs adjacent issue: "Canonical points to redirect".
    - Resolve canonical targets and flag canonical URLs that redirect.
    - This fits the existing canonical metadata rule but needs target
      resolution similar to the links rule.

14. `canonical_points_to_error`
    - Ahrefs adjacent issues: "Canonical points to 4XX" and "Canonical points
      to 5XX".
    - Resolve canonical targets and flag non-success responses.

### Medium Fit

15. `multiple_title_tags`
    - Ahrefs documented issue: "Multiple title tags".
    - Current metadata rule checks missing/long/repeated title, but not
      multiple `<title>` elements.

16. `multiple_meta_descriptions`
    - Ahrefs documented issue: "Multiple meta description tags".
    - Current metadata rule checks missing/short/long description, but not
      duplicate description tags on the same page.

17. `empty_h1`
    - Ahrefs documented issue: "H1 tag missing or empty".
    - Current `missing_h1` only checks the element count. An empty `<h1>` should
      be reported separately or treated as missing.

18. `page_has_no_outgoing_links`
    - Ahrefs documented issue: "Page has no outgoing links".
    - Detect indexable HTML pages with zero meaningful outgoing anchors.
    - The rule should ignore skipped Rails/CDN/mail/tel links consistently with
      the current links rule.

19. `orphan_page`
    - Ahrefs documented issue: "Orphan page".
    - Similar to `canonical_no_internal_inlinks`, but for page URL rather than
      final canonical URL.
    - This overlaps with a configurable `low_dofollow_inlinks` threshold of
      one, so avoid double-reporting.

20. `non_canonical_page_in_sitemap`
    - Ahrefs documented issue: "Non-canonical page in sitemap".
    - Current `canonical_mismatch` flags the page-level mismatch; this new code
      would explicitly state the sitemap contract violation.

21. `duplicate_pages_without_canonical`
    - Ahrefs documented issue: "Duplicate pages without canonical".
    - Current uniqueness rules find duplicate content/title/description. This
      would connect duplicate clusters to canonical presence and consistency.

22. `url_double_slash`
    - Ahrefs documented issue: "Double slash in URL".
    - Detect sitemap or internal-link URLs whose path contains accidental
      double slashes.
    - Low implementation cost, but lower impact than link/indexability checks.

23. `url_too_long`
    - Ahrefs Page Explorer exposes URL length.
    - Useful as a notice-level metadata/url hygiene check.

24. `structured_data_missing_type`
    - Ahrefs structured-data docs call out missing `@type`.
    - Current schema validation may catch this for registered schemas, but a
      generic issue code would make raw schema.org failures easier to act on.

25. `structured_data_invalid_type`
    - Ahrefs structured-data docs call out invalid schema types.
    - Could be implemented only if Crawlscope adopts or vendors a schema.org
      vocabulary source; otherwise keep using configured JSON schemas.

26. `structured_data_invalid_property`
    - Ahrefs structured-data docs call out invalid schema properties.
    - Same caveat as invalid type: this needs schema.org vocabulary validation,
      not only local JSON schemas.

### Lower Fit Or Requires External Data

27. `noindex_page_became_indexable`
    - Ahrefs match: "Noindex page became indexable".
    - Requires historical crawl snapshots. Not a good fit until Crawlscope has
      persistence or report comparison.

28. `h1_changed`, `meta_description_changed`, `title_tag_changed`,
    `serp_title_changed`
    - Ahrefs match: changed-content issues.
    - Requires prior crawl snapshots or external SERP data. Not a current
      stateless gem fit.

29. `page_and_serp_titles_do_not_match`
    - Ahrefs match: SERP title mismatch.
    - Requires search-result data. Out of scope for a deterministic sitemap
      crawler unless a host app injects SERP observations.

30. `pages_added_to_sitemaps`
    - Ahrefs match: "Pages added to sitemaps".
    - Requires comparing current sitemap URLs with a prior crawl.

31. `pages_to_submit_to_indexnow`
    - Ahrefs match: "Pages to submit to IndexNow".
    - Requires change detection and an IndexNow integration. Better as a host
      app workflow than a default Crawlscope rule.

32. `google_rich_results_validation_error`
    - Ahrefs match: "Structured data has Google rich results validation error".
    - Crawlscope can validate local schema contracts today, but Google rich
      result validation requires Google-specific rule coverage and may diverge
      from schema.org validation. Add only if the gem owns those feature
      schemas explicitly.

## Recommended First Batch

1. Add a shared robots directive parser and emit `nofollow_meta`,
   `noindex_follow_*`, and `noindex_nofollow_*`.
2. Extend link extraction with follow state and emit `nofollow_internal_outlinks`,
   `only_nofollow_internal_inlinks`, `mixed_follow_internal_inlinks`, and
   `low_dofollow_inlinks`.
3. Add canonical target checks:
   `canonical_no_internal_inlinks`, `canonical_points_to_redirect`, and
   `canonical_points_to_error`.
4. Add sitemap consistency aliases for already-observed conditions:
   `sitemap_noindex_url`, `sitemap_redirect_url`, and
   `non_canonical_page_in_sitemap`.
5. Add simple metadata hygiene checks:
   `multiple_title_tags`, `multiple_meta_descriptions`, and `empty_h1`.

