# Scope

MoonCache is an HTTP cache semantics library and a small cache runtime. It sits
between an application and a transport:

```text
application request
  -> normalized metadata
  -> variant lookup
  -> policy decision
  -> transport fetch or cached response
  -> store update and trace
```

## In scope for 0.1.3

- `GET` and `HEAD` cache decisions.
- Private and shared cache modes.
- RFC 9111 cacheability, age, and freshness rules needed by the runtime.
- `Cache-Control`, `Date`, `Age`, `Expires`, `ETag`, `Last-Modified`, and
  `Vary` values required by those rules.
- Multiple variants for one normalized URI.
- Conditional revalidation and `304` metadata merging.
- An in-memory HTTP cache with deterministic capacity eviction.
- A transport-independent synchronous runtime and deterministic test
  transports. The core API is intentionally free of network and filesystem IO.
- An optional direct `f4ah6o/http11` conversion package.
- A native-only minimal `moonbitlang/async/http` transport and async runtime
  wrapper, isolated from the portable core.
- Stable reason codes and redacted text/JSON decision reports.
- A CLI for validating, explaining, and replaying deterministic scenarios.

## Deliberately out of scope

- HTTP wire encoding, DNS, TCP, TLS, QUIC, cookies, redirects, and connection
  pooling.
- Range/206 caching, streamed partial bodies, distributed caches, and CDN purge
  protocols.
- A production reverse proxy.
- A general-purpose LRU or key/value database.
- Direct system-clock reads in the policy layer.

## Security defaults

The default policy is conservative. `no-store`, incomplete responses,
`Vary: *`, unknown status codes without explicit freshness, and shared-cache
responses that can expose private or authorized content are rejected. Trace
renderers redact credential-bearing fields.

## Portability

The model, policy, variant, validation, trace, and memory-store packages are
designed to check on native, JavaScript, and wasm-gc targets. IO adapters are
isolated so target-specific dependencies do not leak into the core. The CLI and
async HTTP adapter intentionally declare native-only target support.
