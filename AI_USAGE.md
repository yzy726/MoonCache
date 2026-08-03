# AI-assisted development

MoonCache uses AI-assisted coding as an engineering tool. AI output is not
accepted solely because it compiles.

## Recorded assistance

- Repository structure, documentation drafts, and CI setup.
- Independent implementation drafts for normalized models, policy arithmetic,
  variants, validation, store, runtime, traces, CLI, and tests.
- Test-case generation from project requirements and RFC rule families.

## Review and verification

Every milestone is formatted and checked with the MoonBit toolchain. Public
interface diffs are reviewed, deterministic unit/contract/end-to-end tests are
run, and native/JavaScript/wasm-gc checks are part of final acceptance.

The implementation is written from the requirements and specifications listed
in `REFERENCES.md`. It does not intentionally include copied third-party source
code. If a future contribution ports code, its copyright and license must be
preserved and recorded in `THIRD_PARTY.md`.

## Human decisions

Maintainers remain responsible for release approval, security decisions,
compatibility promises, license review, and interpreting any RFC ambiguity.
