# Release checklist

## Published `0.2.0` release

- [x] module version and Apache-2.0 license declared
- [x] policy, Vary, validation, 304, MemoryStore, Runtime, Trace, and CLI
- [x] optional HTTP11 and native async adapters
- [x] native recoverable FileStore with recovery and quarantine tooling
- [x] request coalescing with cancel/error guarantees
- [x] stale extensions, background revalidation, observers, telemetry
- [x] full CLI: explain/validate/replay/stats/inspect/purge/verify/clean/serve
- [x] demo proxy example plus local `serve` command
- [x] 290 deterministic rule-scenario fixtures (250+ floor enforced in tests)
- [x] differential compatibility fixtures with classification method
- [x] deterministic benchmarks via `moon bench`
- [x] five self-checking runnable examples including demo proxy
- [x] warning-denying checks and tests
- [x] native, JavaScript, and wasm-gc core verification
- [x] generated public interfaces
- [x] RFC, Store, testing, security, limitation, dependency, and AI records
- [x] roadmap and migration notes
- [x] milestone-oriented Git history

## Migration from 0.1.x to 0.2.0

The public API of the core packages is source-compatible with `0.1.3`. The
following additions and behavior notes apply when upgrading:

1. New packages are additive only: `Ag108/MoonCache/persistence/file_store`,
   `Ag108/MoonCache/concurrency`, `Ag108/MoonCache/adapters/async_http`
   (promoted from experimental), and the CLI store commands.
2. The scenario JSON schema gains no required fields; existing `0.1.x`
   scenario files replay unchanged. Fixtures generated for `0.2.0` live under
   `testdata/scenarios/` with numeric prefixes.
3. Reason-code strings remain stable; new codes added in `0.2.0` start at new
   family numbers and never renumber existing codes.
4. The CLI keeps all `0.1.x` commands and exit codes. New store-backed
   commands (`stats`, `inspect`, `purge`, `verify`, `clean`, `serve`) return
   exit code `2` on invalid arguments or unreadable stores.
5. `FileStore::open` creates its directory layout on demand and replays a
   recovery scan; callers upgrading from memory-only setups should review
   `docs/SECURITY_MODEL.md` for on-disk privacy guarantees before enabling.

## Published `0.1.3` release

- [x] module version and Apache-2.0 license declared
- [x] policy, Vary, validation, 304, MemoryStore, Runtime, Trace, and CLI
- [x] optional HTTP11 and native async adapters
- [x] four self-checking runnable examples
- [x] more than 120 deterministic rule scenarios
- [x] warning-denying checks and tests
- [x] native, JavaScript, and wasm-gc core verification
- [x] generated public interfaces
- [x] RFC, Store, testing, security, limitation, dependency, and AI records
- [x] milestone-oriented Git history

## Publication record

- Source repository: <https://github.com/yzy726/MoonCache>
- Package page: <https://mooncakes.io/docs/Ag108/MoonCache>
- Install command: `moon add Ag108/MoonCache@0.2.0`

## Release verification commands

```bash
moon fmt --check
moon info
git diff --exit-code
moon check --target native --deny-warn
moon check --target js --deny-warn
moon check --target wasm-gc --deny-warn
moon test --target native --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon package --list
```

Run all CLI smoke commands and examples from `TESTING.md`, then inspect the
package list for generated build output, credentials, local paths, or other
files that must not be published.

## Versioning

Reason-code strings are compatibility-sensitive. Public `.mbti` changes,
scenario-schema changes, and adapter dependency upgrades must be called out in
`CHANGELOG.md`. The `0.1.x` series was pre-stable; the `0.2.0` final-acceptance release keeps reason codes and the scenario schema stable, and breaking changes now require a minor-version bump with a migration note here.
