# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0] - 2026-07-24


### Added

- report Server-Timing metrics

- authenticate timing crawl requests




### Fixed

- use portable crawl configuration defaults



## [0.7.2] - 2026-07-23


### Fixed

- preserve host configuration



## [0.7.1] - 2026-07-21


### Added

- add lazy install generator



## [0.7.0] - 2026-07-21


### Added

- add commitlint and lefthook

- add lazy Rails task entrypoint



## [0.6.0] - 2026-06-01


### Added

- add bounded async crawl execution




### Changed

- default HTTP crawling to async

- update Ruby CI matrix




### Fixed

- respect noindex targets in sitemap link audit

- improve validation report readability



## [0.5.0] - 2026-05-31


### Added

- expand SEO audit checks



## [0.4.0] - 2026-05-21


### Added

- add indexability and content quality checks




### Fixed

- preserve release changelog history

- scope content ratio to main content

- harden indexability and uniqueness rules



## [0.3.0] - 2026-04-28


### Added

- add JobPost structured data




### Documentation

- fix missing changelog entry




### Fixed

- ldjson check now uses the same convention for default URL



## [0.2.0] - 2026-04-24


### Changed

- simplify crawl and structured data boundaries

- harden validation boundaries




### Fixed

- handle child sitemaps

- use URL for sitemap validation



## [0.1.0] - 2026-04-23


### Added

- add crawlkit release-ready audit gem

- add standalone validation commands

- move default schema rules into crawlkit




### Changed

- strengthen public API coverage

- load shared test dependencies

- rename crawlkit to crawlscope



