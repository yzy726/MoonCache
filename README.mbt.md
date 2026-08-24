# MoonCache

MoonCache is a transport-independent, explainable HTTP cache policy and
runtime toolkit for MoonBit. It implements the `0.2.0` cache lifecycle:

```text
Request
  -> normalized cache key
  -> Store lookup
  -> Vary selection
  -> freshness decision
  -> Fetch or conditional revalidation
  -> 304 merge or replacement
  -> Store update
  -> RuntimeResponse + CacheTrace
```

It is an HTTP caching semantics layer, not an HTTP protocol stack, generic LRU,
cookie jar, or production reverse proxy.

## Release status

The `0.2.0` release includes:

- normalized request, response, header, URI, and saturating time models;
- private/shared storage rules and authenticated-request protection;
- RFC 9111 corrected age and freshness calculations;
- `Vary` variants with missing-versus-empty field semantics;
- ETag and Last-Modified conditional requests;
- `304 Not Modified` metadata merging with cached-body retention;
- an HTTP-specific `MemoryStore` with deterministic eviction and limits;
- a native recoverable `FileStore` with atomic writes, digests, quarantine,
  and compaction;
- deterministic request coalescing for concurrent identical fetches;
- stale resilience: `stale-if-error`, `stale-while-revalidate`,
  `only-if-cached`, background revalidation, observers, and telemetry;
- a complete transport-independent `CachedRuntime`;
- deterministic `FakeTransport` and `RecordingTransport`;
- redacted text/JSON trace, runtime, and Store statistics reports;
- a native CLI with scenario commands plus store-backed
  `stats`/`inspect`/`purge`/`verify`/`clean` and a demo caching proxy (`serve`);
- optional `f4ah6o/http11` and native `moonbitlang/async/http` adapters;
- five runnable, self-checking examples including a demo proxy walkthrough;
- 290 data-driven rule scenarios, differential compatibility fixtures, and
  deterministic benchmarks — no public-network or real-wait tests.

- Source: [yzy726/MoonCache](https://github.com/yzy726/MoonCache)
- Package: [Ag108/MoonCache](https://mooncakes.io/docs/Ag108/MoonCache)
- License: Apache-2.0

## Build and test

```bash
moon fmt --check
moon check --deny-warn
moon test --deny-warn
```

The portable packages are also checked explicitly:

```bash
moon check --target native --deny-warn
moon check --target js --deny-warn
moon check --target wasm-gc --deny-warn
```

Add the published release with:

```bash
moon add Ag108/MoonCache@0.2.0
```

## Minimal cached runtime

Add the root package to `moon.pkg`:

```moonbit nocheck
///|
import {
  "Ag108/MoonCache" @mooncache,
}
```

Then inject a Store, a Transport, and time:

```moonbit nocheck
let store = @mooncache.MemoryStore::default()
let origin = @mooncache.FakeTransport::new([
  @mooncache.TransportResponse::new(
    @mooncache.ResponseMeta::complete(
      200,
      @mooncache.HeaderMap::from_pairs([
        ("Cache-Control", "max-age=60"),
      ]),
      @mooncache.Timestamp::zero(),
      @mooncache.Timestamp::zero(),
    ),
    b"hello",
  ),
])
let runtime = @mooncache.CachedRuntime::new(
  store,
  origin,
  @mooncache.CacheOptions::private_cache(),
)
let request = @mooncache.RuntimeRequest::get(
  "https://example.test/greeting",
)
let first = try! runtime.execute(request, @mooncache.Timestamp::zero())
let second = try! runtime.execute(
  request,
  @mooncache.Timestamp::from_seconds(10L),
)
println(first.source.label())  // upstream
println(second.source.label()) // cache
```

`CacheStore` and `Transport` are open traits, so applications can replace both
implementations without changing policy code.

## CLI

Scenario commands consume deterministic JSON and never perform a network
request:

```bash
moon run cmd/main -- explain examples/scenarios/stale-etag.json
moon run cmd/main -- explain examples/scenarios/stale-etag.json --json
moon run cmd/main -- validate examples/scenarios/basic-cache.json
moon run cmd/main -- replay testdata/scenarios
moon run cmd/main -- replay testdata/scenarios --json
```

`replay` sorts paths explicitly and continues after an unreadable or malformed
individual file, returning a failing exit code with a complete summary.

Native `FileStore` directories can be inspected without a running process:

```bash
moon run cmd/main -- stats --store .cache/mooncache --json
moon run cmd/main -- inspect --store .cache/mooncache
moon run cmd/main -- purge --store .cache/mooncache --uri https://example.test/data
moon run cmd/main -- verify --store .cache/mooncache
moon run cmd/main -- clean --store .cache/mooncache
```

## Demo proxy

`serve` runs a local caching reverse proxy for one upstream origin. It exists
to demonstrate the runtime end to end (MISS, HIT, REVALIDATE, 304,
STALE-IF-ERROR, VARY, coalescing) and is not part of the library API:

```bash
moon run cmd/main -- serve --listen 127.0.0.1:8080 --upstream 127.0.0.1:9000 \
  [--store .cache/mooncache]
```

The demo proxy is explicitly **not**:

- a production reverse proxy;
- TLS terminating (HTTP only);
- CONNECT capable (no tunneling);
- HTTP/2 or HTTP/3 aware;
- suitable for untrusted public traffic.

## Runnable examples

```bash
moon run examples/basic_cache
moon run examples/vary_language
moon run examples/etag_revalidation
moon run examples/shared_private
moon run examples/demo_proxy
```

| Example               | Demonstrates                                                     |
| --------------------- | ---------------------------------------------------------------- |
| `basic_cache`       | first request misses, second request hits                        |
| `vary_language`     | English and Chinese variants remain independent                  |
| `etag_revalidation` | stale ETag request receives 304 and retains its body             |
| `shared_private`    | private cache reuses a private response; shared cache rejects it |
| `demo_proxy`        | full MISS/HIT/REVALIDATE/304/STALE-IF-ERROR/VARY/coalescing walk |

Every example checks its own expected source, body, variant count, or origin
call count and exits unsuccessfully on a regression.

## Optional adapters

### HTTP11

`adapters/http11` directly converts `f4ah6o/http11@0.1.1` request and response
types. Origin-form request targets require the caller to supply the absolute
URI:

```moonbit nocheck
///|
let cached_request = @mooncache_http11.request_to_runtime_at_uri(
  wire_request, "https://example.test/data", request_time,
)
```

The core package does not import HTTP11.

### Native async HTTP

`adapters/async_http` provides `AsyncTransport`,
`MoonbitAsyncHttpTransport`, `ScriptedAsyncTransport`, and
`AsyncCachedRuntime`. The real transport currently supports GET, POST, and PUT
through `moonbitlang/async/http@0.20.2` and receives an injected response clock:

```moonbit nocheck
///|
let origin = @mooncache_async.MoonbitAsyncHttpTransport::new(clock)

///|
let client = @mooncache_async.AsyncCachedRuntime::new(
  @mooncache.MemoryStore::default(),
  origin,
  @mooncache.CacheOptions::private_cache(),
)

///|
let response = client.execute(request, now)
```

The adapter is native-only; model and policy portability do not depend on it.
See [Async adapter](docs/ASYNC_ADAPTER.md).

## Security defaults

- `no-store`, incomplete bodies, `Vary: *`, and unknown statuses without
  explicit freshness are not stored.
- Shared caches reject `private` responses and authorized requests unless an
  explicit option/rule permits them.
- `Authorization`, `Proxy-Authorization`, `Cookie`, and `Set-Cookie` values
  are redacted from reports.
- MemoryStore strips hop-by-hop response fields, strips `Set-Cookie` by
  default, and removes request credentials unless a `Vary` field requires one.
- Body size, total body bytes, and entry count are bounded.
- Age arithmetic saturates and clamps backward clocks.
- Core policy never reads a system clock or accesses the network.

Read the [security model](docs/SECURITY_MODEL.md) before integrating a shared
cache.

## Documentation

- [Scope and boundaries](docs/SCOPE.md)
- [Architecture](docs/DESIGN.md)
- [Cache model](docs/CACHE_MODEL.md)
- [RFC support matrix](docs/RFC_SUPPORT.md)
- [Decision codes](docs/DECISION_CODES.md)
- [Store contract](docs/STORE_CONTRACT.md)
- [Async adapter](docs/ASYNC_ADAPTER.md)
- [Testing](docs/TESTING.md)
- [Compatibility](docs/COMPATIBILITY.md)
- [Limitations](docs/LIMITATIONS.md)
- [Release checklist](docs/RELEASE.md)
- [Specifications and references](REFERENCES.md)
- [Third-party software](THIRD_PARTY.md)
- [AI-assisted development record](AI_USAGE.md)

The generated root interface is
[`pkg.generated.mbti`](pkg.generated.mbti). Adapter packages have their own
generated interfaces after `moon info`.

## License

Apache-2.0. See [LICENSE](LICENSE).
