# Current-release limitations

The following are deliberate boundaries of `0.1.2`, not hidden claims of
support.

## Cache semantics

- No Range/206 partial-response cache.
- No stale-if-error fallback after connection failures or 5xx responses.
- No stale-while-revalidate background work.
- No Warning header synthesis.
- No request coalescing/singleflight.
- No redirect-chain cache-key policy.
- No streaming or unbounded body storage.
- Caller conditional requests are preserved, but a full origin-server
  precondition evaluator is out of scope.

## Storage

- MemoryStore only; no FileStore or cross-process recovery.
- No distributed consistency or multi-level cache coordination.
- Eviction is deterministic but intentionally simple and single-process.
- Store counters are cumulative across `clear`.

## Networking

- The portable runtime is synchronous and transport-independent.
- The native async HTTP adapter supports buffered GET, POST, and PUT.
- Its origin path performs a planning lookup followed by a replay lookup.
- No adapter-level timeout, redirect, proxy, streaming, or cancellation policy.
- No bundled production proxy or public-server listener.

## CLI

- `explain`, `validate`, and `replay` analyze files only.
- No persistent Store inspection, purge, repair, or serve commands.
- Scenario `upstream_response` is reserved for richer replay and is not used by
  the pure policy analyzer.

## Publication

- Source repository: <https://github.com/yzy726/MoonCache>
- Package page: <https://mooncakes.io/docs/Ag108/MoonCache>

Unsupported features must not be inferred from future plans or issue
discussions.
