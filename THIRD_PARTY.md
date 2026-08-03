# Third-party software

MoonCache contains no vendored or directly ported third-party implementation
source. Dependencies are resolved by Moon and remain separate works governed
by their own licenses.

| Module | Locked version | Purpose | License | Upstream |
|---|---:|---|---|---|
| `moonbitlang/x` | `0.4.46` | native CLI filesystem and process arguments | Apache-2.0 | <https://github.com/moonbitlang/x> |
| `moonbitlang/async` | `0.20.2` | isolated native async HTTP adapter | Apache-2.0 | <https://github.com/moonbitlang/async> |
| `f4ah6o/http11` | `0.1.1` | optional HTTP11 request/response conversion package | Apache-2.0 | <https://mooncakes.io/docs/f4ah6o/http11> |

Exact direct versions are declared in `moon.mod`; the resolved dependency
state is managed under `.mooncakes`.

The HTTP cache behavior is independently implemented from RFC 9111. Public
behavior and API boundaries from projects listed in `REFERENCES.md` were used
for research only. No source from `http-cache-semantics`, a generic LRU
implementation, or the HTTP11 dependency was copied into the MoonCache core.

Any future vendored or directly ported code must record its source, version,
copyright, license, modification status, and affected files here.
