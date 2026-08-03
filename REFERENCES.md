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
