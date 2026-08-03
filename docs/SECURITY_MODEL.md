# Security model

Incorrect shared caching can disclose one user's data to another. MoonCache
therefore prefers a cache miss over uncertain reuse.

## Trust boundaries

- Applications and adapters supply request/response metadata and timestamps.
- Transports control network IO but do not decide cache policy.
- Stores retain potentially sensitive metadata and bodies.
- Trace/report consumers are considered less trusted than runtime memory.

## Enforced initial invariants

- `no-store` never enters MemoryStore.
- Incomplete bodies never enter MemoryStore.
- `Vary: *` is never reusable.
- Shared mode rejects `private` responses.
- Shared mode rejects authorized-request responses unless explicit cache
  directives/options permit reuse.
- Vary selection distinguishes missing and empty fields.
- Age and freshness arithmetic cannot wrap negative.
- Body count and byte limits are applied before retention.
- Hop-by-hop response headers are removed from stored entries.
- Set-Cookie is removed by default.
- Request credentials are removed unless required by Vary.
- Text and JSON reports redact Authorization, Proxy-Authorization, Cookie, and
  Set-Cookie values.
- Unsafe-method related invalidation accepts only safely resolved same-origin
  Location and Content-Location values.

## Integrator responsibilities

- Use private mode for per-user clients unless shared behavior is intended.
- Partition Stores when application identity or tenant boundaries require more
  isolation than HTTP metadata expresses.
- Supply trustworthy absolute URIs and request/response times.
- Apply transport-level header and body limits before allocating unbounded
  data.
- Do not log response bodies merely because metadata reports are redacted.
- Review async adapter limitations before using it for real traffic.
- Do not expose the example programs or CLI as a network proxy.

## Unsupported threat models

The initial release is not a hardened multi-tenant CDN, reverse proxy, or
untrusted persistent cache. It has no disk format, crash recovery, distributed
coordination, TLS termination, or sandbox.

See the top-level `SECURITY.md` for responsible disclosure guidance.
