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
run, and native/JavaScript/wasm-gc checks are part of final acceptance. The
initial implementation contains 280 deterministic test blocks, four
self-checking examples, CLI smoke fixtures, an optional HTTP11 contract suite,
and a native async adapter suite that performs no public-network access.

AI-produced changes were divided into milestone commits. Each milestone ran
`moon info`, formatting, warning-denying checks, and tests before its Git
commit. The final acceptance pass additionally runs all supported targets,
the CLI commands, examples, and package-content inspection.

The implementation is written from the requirements and specifications listed
in `REFERENCES.md`. It does not intentionally include copied third-party source
code. If a future contribution ports code, its copyright and license must be
preserved and recorded in `THIRD_PARTY.md`.

## Human decisions

Maintainers remain responsible for release approval, security decisions,
compatibility promises, license review, and interpreting any RFC ambiguity.
Repository publication and mooncakes.io authentication are deliberately not
performed without maintainer-owned destinations and credentials.
