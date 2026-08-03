# Design

## Dependency direction

```text
model
  |
  +--> policy
  +--> variant
  +--> validation
          |
          v
       trace + store
          |
          v
        runtime
          |
          v
      CLI / examples / adapters
```

The policy packages do not depend on a transport, filesystem, CLI, or concrete
store. Every time value is supplied by the caller.

## Package responsibilities

### Model

Owns normalized header maps, request/response metadata, bounded non-negative
time deltas, cache options, bodies, and stored entries. Header names are
case-insensitive; values retain their original text.

### Policy

Parses only the cache directives needed for decisions. It computes response
cacheability, corrected age, freshness lifetime, request constraints, and a
single explicit action. Arithmetic saturates instead of wrapping.

### Variant

Normalizes absolute HTTP(S) URIs, creates a primary cache key, captures the
request fields named by `Vary`, and compares variants. A missing field and a
present-but-empty field are distinct.

### Validation

Creates conditional request fields from ETag and Last-Modified validators,
preserves caller conditions, and merges eligible `304` metadata while retaining
the cached body.

### Store

Exposes an HTTP-specific cache contract. `MemoryStore` maintains all variants
for a primary key, applies entry/body capacity limits, replaces equal variants,
records access deterministically, and invalidates every variant for a URI.

### Runtime

Orchestrates lookup, matching, evaluation, transport execution, revalidation,
store updates, and returned traces. Transports are injected and can be fully
deterministic.

### Trace and CLI

Every terminal decision includes stable reason codes and relevant arithmetic.
Renderers remove sensitive header values. The CLI consumes deterministic
scenario files; it does not perform network requests.

## Determinism

When two calls receive equal metadata, options, stored entries, and `now`, they
must return equal decisions. No core code reads wall-clock time or waits.

## Error handling

Malformed optional HTTP metadata is ignored conservatively and recorded in the
trace when useful. Invalid required scenario data is reported as a validation
error. Library APIs return explicit result values rather than terminating the
process.

## Public API policy

Only types required to integrate a store, transport, or policy call are public.
Implementation helpers remain package-private. Generated `.mbti` files are
reviewed at every milestone to catch accidental API expansion.
