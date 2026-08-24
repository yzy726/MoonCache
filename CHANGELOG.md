# Changelog

All notable changes are documented here.

## 0.2.0 - 2026-08-24

### Added

- Store-backed CLI commands: `inspect`, `stats`, `purge`, `verify`, and
  `clean` operating on native `FileStore` directories.
- Local demonstration caching proxy (`mooncache serve`) for development use.
- Runnable `demo_proxy` example walking through the MISS/HIT/REVALIDATE/304/
  STALE-IF-ERROR/VARY/COALESCE script.
- Behavior-compatibility fixtures with documented reference expectations.
- Deterministic benchmarks for age calculation, variant matching, and store
  operations.
- Expanded data-driven rule-scenario fixtures (250+) replayed in tests.
- Roadmap, migration, and release documentation updates.

### Changed

- Final-acceptance release published as `0.2.0`.

## 0.1.3 - 2026-08-03

### Fixed

- Replaced the legacy native CLI argument binding with `moonbitlang/core/env`
  so Linux builds link against the current MoonBit runtime.
- Preserved documented CLI argument handling and nonzero process exit codes.
- Updated generated interfaces for the current MoonBit formatter.

## 0.1.2 - 2026-08-03

### Added

- Normalized HTTP request, response, header, URI, key, and safe time models.
- RFC 9111 cacheability, corrected age, freshness, and request-policy rules.
- Private/shared mode, authorization protection, and stable reason codes.
- Vary variant creation, selection, and replacement.
- ETag/Last-Modified conditional requests and 304 metadata merging.
- HTTP-specific MemoryStore with limits, sanitization, deterministic eviction,
  invalidation, and statistics.
- Complete transport-independent CachedRuntime with Fake and Recording
  transports.
- Redacted text/JSON CacheTrace, RuntimeResponse, and StoreStats reports.
- Native explain/validate/replay CLI and deterministic scenario fixtures.
- Optional HTTP11 and native async HTTP adapters.
- Four self-checking runnable examples.
- Cross-target CI, generated API interfaces, and initial release documentation.

### Security

- Conservative no-store, incomplete-body, Vary-star, private/shared, and
  authorized-request defaults.
- Sensitive diagnostic fields are redacted and stored metadata is sanitized.

Source and package pages:

- <https://github.com/yzy726/MoonCache>
- <https://mooncakes.io/docs/Ag108/MoonCache>
