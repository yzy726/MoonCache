# Testing

All core tests are deterministic: they inject timestamps, perform no real
waits, and do not access the public network.

## Current initial-acceptance inventory

The repository contains 279 MoonBit test blocks.

| Family | Named tests |
|---|---:|
| policy age/freshness | 22 |
| cacheability | 22 |
| policy decisions | 22 |
| Cache-Control parser | 20 |
| URI variants | 18 |
| Vary matching | 17 |
| validators/conditional requests | 17 |
| 304 merge | 13 |
| MemoryStore | 21 |
| core Runtime end-to-end | 15 |
| invalidation | 11 |
| native async adapter | 6 |
| HTTP11 adapter | 8 |
| CLI parser/reporting | 12 |
| remaining models, reports, dates, and scenarios | 55 |

Test names include at least:

- 38 malformed, invalid, overflow, clock, empty, unknown, or incomplete cases;
- 18 Vary cases;
- 41 ETag, Last-Modified, validator, revalidation, or 304 cases;
- 16 private/shared difference cases;
- 15 complete core Runtime cases, plus native async lifecycle cases.

## Local commands

```bash
moon fmt --check
moon check --deny-warn
moon test --deny-warn
moon info
```

Portable target checks:

```bash
moon check --target native --deny-warn
moon check --target js --deny-warn
moon check --target wasm-gc --deny-warn
moon test --target native --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
```

Native adapter checks:

```bash
moon test adapters/http11 --target native --deny-warn
moon test adapters/async_http --target native --deny-warn
```

CLI smoke checks:

```bash
moon run cmd/main -- explain examples/scenarios/stale-etag.json
moon run cmd/main -- validate examples/scenarios/basic-cache.json
moon run cmd/main -- replay testdata/scenarios
```

Runnable examples:

```bash
moon run examples/basic_cache
moon run examples/vary_language
moon run examples/etag_revalidation
moon run examples/shared_private
```

## Interface review

`moon info` regenerates each `pkg.generated.mbti`. Review those diffs before a
commit. An unexpected interface change is treated as an API change even when
tests still pass.

## Scenario files

CLI scenarios use JSON with `name`, `mode`, `now`, `request`, optional
`stored_response`, optional `upstream_response`, and optional `expected`.
`expected.action` accepts canonical action labels and documented short aliases;
`expected.reason` uses a stable `MC_*` code.
