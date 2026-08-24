# Benchmarks

MoonCache ships deterministic micro-benchmarks built on the MoonBit benchmark
harness. They inject fixed timestamps and scripted transports, so results are
repeatable on the same machine and never touch the network or wall clock.

## Running

```bash
moon bench
```

Benchmarks run in release mode against the native target.

## Inventory

| Benchmark | Location | Measures |
|---|---|---|
| policy decision | `bench.mbt` (`evaluate_cached_response`) | storage + corrected-age + freshness pipeline for one cached response, 1000 iterations |
| variant keys | `bench.mbt` (`build_variant_key`) | two-field `Vary` canonicalization over 2000 requests with rotating header values |
| MemoryStore lookup | `bench.mbt` (`find_variants`) | put of 64 variants then 4000 primary-key lookups |
| runtime execute | `bench.mbt` (`CachedRuntime::execute`) | full request lifecycle (key, lookup, decision, store update) for 500 sequential requests against an always-fresh origin |

## Interpreting results

The harness reports per-benchmark timing through `moon bench`. Compare runs on
the same machine and toolchain version; CI treats benchmarks as smoke checks
(they must pass), not as performance gates.

## Adding benchmarks

Add a new `test (bench : @bench.T)` block to `bench.mbt`, keep it
deterministic (injected clocks, scripted transports only), and use
`bench.keep` so work cannot be optimized away.
