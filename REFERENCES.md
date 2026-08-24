# References

MoonCache is an independent implementation based on public specifications and
behavioral research. No third-party implementation source has been copied into
this repository.

## Normative specifications

- RFC 9110, *HTTP Semantics*:
  <https://www.rfc-editor.org/rfc/rfc9110>
- RFC 9111, *HTTP Caching*:
  <https://www.rfc-editor.org/rfc/rfc9111>
- RFC 3986, *Uniform Resource Identifier (URI): Generic Syntax*:
  <https://www.rfc-editor.org/rfc/rfc3986>

## Ecosystem references

- MoonBit language and toolchain documentation:
  <https://docs.moonbitlang.com/>
- `f4ah6o/http11`, consulted as an example of a separate HTTP field parsing
  layer:
  <https://mooncakes.io/docs/f4ah6o/http11>
- `http-cache-semantics`, consulted only for public behavior and compatibility
  comparisons:
  <https://github.com/kornelski/http-cache-semantics>

## Interpretation policy

RFC 9111 rules take priority. Where the specification permits implementation
choice, MoonCache favors predictable and privacy-preserving behavior and
documents the choice in reason codes and tests. Future differential fixtures
will compare observable action, age, TTL, and validators without importing
reference implementation code.

## Differential compatibility method

`testdata/compat/` holds JSON fixtures that encode scenarios exercised by the
reference library `http-cache-semantics` (BSD-2-Clause) using only public
documentation and observable behavior. Each fixture:

1. describes one request/response/time triple in the shared scenario format;
2. records the decision MoonCache must produce (`expected.action`);
3. names the matching reference behavior in the `compat:` fixture name.

A dedicated test replays every fixture and fails when MoonCache diverges from
the documented reference expectation. No reference source code is imported,
linked, or copied.

### Difference classification

When a divergence appears between MoonCache and a reference implementation it
must be classified as exactly one of:

- `MOONCACHE_BUG`: MoonCache violates RFC 9111 or its own documented behavior;
  fix the implementation and add a regression fixture.
- `RFC_DRIFT`: the reference implements an older RFC (for example RFC 7234)
  where RFC 9111 changed the rule; keep MoonCache aligned with RFC 9111.
- `DESIGN_CHOICE`: both behaviors are permitted; MoonCache keeps its choice
  and documents it here with a reason code.
- `REFERENCE_EXTENSION`: behavior that exists only in the reference for
  legacy-client compatibility; MoonCache treats it as out of scope unless
  adopted through a roadmap item.

Known deliberate design choices (class `DESIGN_CHOICE`): heuristic freshness
is enabled by default but capped at 24 hours; request credentials are stripped
from stored entries rather than refusing storage in private caches; warning
headers are preserved verbatim instead of being rewritten.
