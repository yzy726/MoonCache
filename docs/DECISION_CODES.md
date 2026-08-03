# Decision codes

Reason-code strings are stable machine-facing identifiers. Existing strings
will not be repurposed; a future incompatible meaning requires a new code.

## Storage

| Code | Meaning |
|---|---|
| `MC_STORE_001` | response is eligible for storage |
| `MC_STORE_002` | `no-store` forbids storage |
| `MC_STORE_003` | request method is not cacheable |
| `MC_STORE_004` | status is cacheable by default |
| `MC_STORE_005` | explicit freshness permits storage |
| `MC_STORE_006` | unknown status lacks explicit freshness |
| `MC_STORE_007` | shared cache rejects a private response |
| `MC_STORE_008` | response body is incomplete |
| `MC_STORE_009` | response exceeds a body limit |
| `MC_STORE_010` | Store capacity is disabled |
| `MC_AUTH_001` | shared cache rejects authorized-request reuse |

## Freshness and age

| Code | Meaning |
|---|---|
| `MC_FRESH_001` | lifetime came from `max-age` |
| `MC_FRESH_002` | shared lifetime came from `s-maxage` |
| `MC_FRESH_003` | lifetime came from `Expires` |
| `MC_FRESH_004` | lifetime is heuristic |
| `MC_FRESH_005` | no freshness lifetime exists |
| `MC_FRESH_006` | cached response is fresh |
| `MC_FRESH_007` | cached response is stale |
| `MC_AGE_001` | apparent age was calculated |
| `MC_AGE_002` | corrected current age was calculated |
| `MC_AGE_003` | backward clock movement was clamped |
| `MC_AGE_004` | arithmetic saturated to prevent overflow |

## Request constraints

| Code | Meaning |
|---|---|
| `MC_REQ_001` | request `no-store` bypasses reuse and storage |
| `MC_REQ_002` | request `no-cache` forces validation |
| `MC_REQ_003` | request `only-if-cached` forbids origin access |
| `MC_REQ_004` | request `max-age` constrains reuse |
| `MC_REQ_005` | request `min-fresh` constrains reuse |
| `MC_REQ_006` | request `max-stale` permits stale reuse |

## Vary

| Code | Meaning |
|---|---|
| `MC_VARY_001` | response has no Vary fields |
| `MC_VARY_002` | all Vary fields matched |
| `MC_VARY_003` | a Vary value differed |
| `MC_VARY_004` | `Vary: *` forbids storage |
| `MC_VARY_005` | missing and present Vary fields differed |
| `MC_VARY_006` | `Vary: *` has no reusable variant |

## Validation

| Code | Meaning |
|---|---|
| `MC_REVAL_001` | ETag generated `If-None-Match` |
| `MC_REVAL_002` | Last-Modified generated `If-Modified-Since` |
| `MC_REVAL_003` | both validators were generated |
| `MC_REVAL_004` | caller condition was preserved |
| `MC_REVAL_005` | 304 metadata was merged with the cached body |
| `MC_REVAL_006` | origin returned a replacement response |

## Runtime and Store

| Code | Meaning |
|---|---|
| `MC_RUNTIME_001` | runtime served a cache hit |
| `MC_RUNTIME_002` | no matching entry was found |
| `MC_RUNTIME_003` | runtime bypassed cache reuse |
| `MC_RUNTIME_004` | runtime fetched from injected transport |
| `MC_RUNTIME_005` | origin response was stored |
| `MC_RUNTIME_006` | origin response was not stored |
| `MC_RUNTIME_007` | only-if-cached had no reusable response |
| `MC_MEM_001` | an equal variant was replaced |
| `MC_MEM_002` | entry-count limit caused eviction |
| `MC_MEM_003` | body-byte limit caused eviction |
| `MC_MEM_004` | URI invalidation removed entries |

## Invalidation

| Code | Meaning |
|---|---|
| `MC_INV_001` | successful unsafe method invalidates target |
| `MC_INV_002` | same-origin related URI is also invalidated |
| `MC_INV_003` | safe method does not invalidate |
| `MC_INV_004` | error status does not invalidate |

The canonical code-to-message mapping lives in `reason.mbt`; this document is a
human index, not a second implementation.
