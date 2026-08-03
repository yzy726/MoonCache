# Changelog

All notable changes are documented here.

## 0.1.0 - Unreleased

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

This version remains “Unreleased” until the maintainer completes the public
repository and mooncakes.io publication gates in `docs/RELEASE.md`.
