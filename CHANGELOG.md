# Changelog

All notable changes are documented here.

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
