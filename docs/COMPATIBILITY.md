# Compatibility

## MoonBit toolchain

The initial acceptance was implemented and verified with the MoonBit toolchain
available on 2026-08-03. CI installs the current official toolchain and treats
warnings as errors, so syntax and dependency changes are detected early.

## Targets

| Package family | native | JavaScript | wasm-gc |
|---|---:|---:|---:|
| root model/policy/variant/validation | yes | yes | yes |
| MemoryStore and synchronous Runtime | yes | yes | yes |
| Fake/Recording Transport | yes | yes | yes |
| HTTP11 conversion adapter | yes | checked with portable builds | checked with portable builds |
| CLI | yes | no | no |
| native async HTTP adapter | yes | no | no |
| four deterministic examples | yes | yes | yes |

Target-specific packages declare `supported_targets` so unsupported adapters do
not contaminate portable builds.

## Dependency versions

- `moonbitlang/x@0.4.46`
- `moonbitlang/async@0.20.2`
- `f4ah6o/http11@0.1.1`

The async API is pre-stable. It is intentionally isolated behind
`AsyncTransport`; upgrading it must not alter root package interfaces.

## API stability

`0.1.x` is pre-stable. Stable reason-code strings will not be repurposed, but
public type shapes may evolve before `1.0.0`. Generated `.mbti` diffs are the
authoritative API review artifact.
