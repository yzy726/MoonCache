# Release checklist

## Published `0.1.2` release

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
- Install command: `moon add Ag108/MoonCache@0.1.2`

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
`CHANGELOG.md`. The `0.1.x` series is pre-stable; `1.0.0` requires the broader
stability review and explicit API guarantees.
