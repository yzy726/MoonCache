# Release checklist

## Local `0.1.0` acceptance

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

## Maintainer-owned publication gates

These operations cannot be completed safely from a local implementation task
without the maintainer's external destination and credentials:

- [ ] create or select the public repository
- [ ] set the real `repository` URL in `moon.mod`
- [ ] push the reviewed commit history
- [ ] authenticate to mooncakes.io
- [ ] verify the package name `Ag108/MoonCache` is owned and available
- [ ] publish `0.1.0`
- [ ] install `0.1.0` into a clean external project
- [ ] create the public release/tag and attach the final changelog

Do not invent a repository URL or claim a registry release before these boxes
are completed.

## Pre-publication commands

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
terminal-acceptance work in `goal.md`.
