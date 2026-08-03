# CacheStore contract

`CacheStore` is an open trait. A replacement Store must preserve HTTP-specific
variant behavior rather than acting as an unstructured key/value map.

## Operations

### `find_variants(key)`

- Return every candidate under the exact primary key.
- Do not perform Vary matching; the core `select_variant` function owns it.
- Return defensive entries so caller mutation cannot change stored state.
- Record one logical lookup and hit/miss outcome when statistics are supported.

### `put(entry)`

- Replace an entry with the same primary and variant keys.
- Reject entries whose policy is uncacheable, `no-store`, or `vary_star`.
- Enforce entry, individual-body, and total-body limits.
- Return a precise `StorePutResult`; do not terminate the process.

### `remove_variant(key, variant)`

- Remove only the exact variant.
- Return false when no exact variant exists.

### `invalidate_uri(uri)`

- Normalize the URI using the same cache-key rules.
- Remove every GET/HEAD-compatible variant for that URI.
- Return the number of removed entries.

### `clear()`

- Remove all stored entries and body bytes.
- Operational counters may remain cumulative; `MemoryStore` follows this rule.

### `stats()`

- Return a snapshot with no mutable reference into Store state.
- Keep entry and body-byte gauges consistent after replacement, eviction,
  removal, invalidation, and clear.

## MemoryStore ownership and sanitization

`MemoryStore` deep-copies mutable header collections on input and output.
Stored response headers remove:

- standard hop-by-hop fields;
- every field named by `Connection`;
- `Set-Cookie` by default.

Stored request metadata removes Authorization, Proxy-Authorization, and Cookie
unless a response's `Vary` explicitly requires that field for safe selection.

## Deterministic eviction

Access and insertion use a logical monotonically increasing counter, not wall
time. Capacity enforcement evicts the least-recently accessed record; equal
access order is resolved by insertion order. The algorithm is deliberately
HTTP-specific and is not exposed as a generic LRU.

## Limits

`MemoryStoreOptions` controls:

- maximum entries;
- maximum aggregate body bytes;
- maximum single body bytes;
- Set-Cookie stripping;
- request credential stripping.

Zero/negative capacity disables insertion. Oversized origin responses can still
be returned to the caller; only their storage is rejected.

## Contract verification

`memory_store_test.mbt` covers insertion/find, replacement, multiple variants,
removal, URI invalidation, deterministic entry and byte eviction, oversize
rejection, clear, statistics, deep-copy isolation, hop-by-hop removal, and
sensitive metadata handling. Read-only inspection tests verify that peeking,
enumerating URIs, and counting variants do not alter lookup statistics.
