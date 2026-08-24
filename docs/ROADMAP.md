# Roadmap

MoonCache follows a milestone-oriented roadmap. The `0.2.0` release completes
the final-acceptance scope; later work is additive and must not break the
documented reason codes or the scenario schema.

## Released

### 0.1.x — initial acceptance

- Normalized models, policy core, Vary, validation, 304 merge.
- MemoryStore, CachedRuntime, FakeTransport, Trace, explain CLI.
- Optional HTTP11 and native async HTTP adapters.

### 0.2.0 — final acceptance

- Native recoverable `FileStore` with atomic writes, digests, quarantine,
  compaction, and crash recovery.
- Request coalescing (`RequestGroup`) with cancel/error guarantees.
- Stale extensions: `stale-if-error`, `stale-while-revalidate`,
  `only-if-cached`, background revalidation, telemetry observers.
- Full CLI: `explain`, `validate`, `replay`, `stats`, `inspect`, `purge`,
  `verify`, `clean`, and a local demo proxy via `serve`.
- Differential compatibility fixtures plus classification method.
- Deterministic benchmarks (`moon bench`) and a 290-fixture scenario corpus.

## Next candidates (unordered)

- Range request handling behind an explicit opt-in flag.
- A portable (non-native) persistence layer for JavaScript targets.
- Structured tracing hooks beyond the current observer trait.
- Optional cache-digest style diagnostics for debugging multi-variant URIs.
- Additional adapter packages as upstream MoonBit HTTP clients stabilize.

## Non-goals

These remain out of scope per `SCOPE.md`: production reverse-proxy features,
TLS termination, CONNECT tunneling, distributed invalidation protocols, and a
general-purpose key/value database.
