# Cache model

MoonCache separates cache semantics from transport and storage.

## Request lifecycle

```text
RuntimeRequest
  -> normalize method and absolute HTTP(S) URI
  -> build PrimaryCacheKey
  -> CacheStore.find_variants
  -> select_variant using Vary
  -> evaluate_cached_response
       -> ServeFresh
       -> ServeStale
       -> Revalidate
       -> Fetch
       -> Bypass
       -> OnlyIfCachedMiss
  -> optional Transport.execute
  -> optional 304 merge or replacement
  -> optional Store update/invalidation
  -> RuntimeResponse and CacheTrace
```

## Primary keys

The initial primary key is the normalized method and URI. GET and HEAD share
GET cache entries where the runtime can safely return HEAD metadata without a
body. URI normalization lowercases scheme/host, removes default ports,
normalizes dot segments, and preserves meaningful query text.

Only absolute `http` and `https` URIs produce cache keys. Relative or malformed
URIs conservatively bypass storage and reuse.

## Variants

The response's normalized `Vary` field names define `VariantKey`. Values are
captured from the request that produced the response. A missing request field
and a present field with an empty value are different states.

`Vary: *` never creates a reusable variant. Multiple variants may coexist
under one primary key and equal variants replace each other.

## Time and age

`Timestamp` and `DeltaSeconds` wrap signed 64-bit values behind non-negative,
saturating operations. Callers supply request, response, stored, and current
times. The core computes:

```text
apparent_age
response_delay
corrected_age_value
corrected_initial_age
resident_time
current_age
```

Backward clocks are clamped. Addition and scaling saturate instead of wrapping.
Freshness comes from `s-maxage` in shared mode, `max-age`, `Expires`, or the
configured conservative Last-Modified heuristic.

## Storage policy

Storage eligibility and reuse are distinct decisions. `StoredPolicy` records
the result needed by stores, while `CacheDecision` evaluates a matching entry
for one request and time.

The initial release handles GET and optionally HEAD responses. It recognizes
default-cacheable statuses and explicit freshness for other eligible statuses.
`no-store`, shared `private`, unsafe authorization reuse, incomplete bodies,
unknown statuses without explicit freshness, and `Vary: *` are rejected.

## Revalidation

Stale entries with validators produce a conditional request:

- ETag becomes `If-None-Match`;
- Last-Modified becomes `If-Modified-Since`;
- both can be sent together;
- caller-supplied conditions are preserved rather than overwritten.

A 304 response updates eligible metadata and policy while retaining the cached
body. A normal response replaces the selected variant.

## Invalidation

Successful unsafe methods invalidate all variants for the target URI.
Same-origin `Location` and `Content-Location` values may add related targets.
Cross-origin and malformed related values are ignored.

## Explainability

Every terminal action carries `CacheTrace`, stable reason codes, age arithmetic,
selected keys, validator kind, and generated conditional headers. Text and JSON
reports redact credential and cookie values.
