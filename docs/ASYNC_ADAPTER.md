# Native async HTTP adapter

The initial adapter lives in `adapters/async_http` and is restricted to the
native target. This keeps `moonbitlang/async`, networking, and its evolving API
out of the portable core.

## Public pieces

- `AsyncTransport`: async origin abstraction.
- `MoonbitAsyncHttpTransport`: real `moonbitlang/async/http` bridge.
- `ScriptedAsyncTransport`: deterministic offline origin.
- `AsyncCachedRuntime`: async wrapper around the portable cache lifecycle.
- header conversion helpers for the async client's `Map[String, String]`.

## Why a separate async trait?

The core `Transport` is synchronous so policy, Store, FakeTransport, and runtime
tests compile on native, JavaScript, and wasm-gc. The adapter's `AsyncTransport`
represents the suspension boundary without forcing every core caller to depend
on native async IO.

## Runtime bridge

`AsyncCachedRuntime` uses the portable runtime as the single source of cache
semantics:

```text
portable runtime + recording probe
  -> cache hit: return immediately
  -> origin required: capture exact request
       -> AsyncTransport.execute
       -> replay one response through portable runtime
       -> normal Store update / 304 merge / invalidation
```

This preserves conditional headers and avoids duplicating RFC decisions in the
adapter. An origin path performs a second Store lookup during replay, so Store
lookup counters include planning overhead. This is a documented initial adapter
trade-off; a future formal async runtime can share a public execution plan.

## Real HTTP support

`MoonbitAsyncHttpTransport` currently maps:

- GET without a body;
- POST with a buffered body;
- PUT with a buffered body.

HEAD, DELETE, PATCH, streaming bodies, redirects, proxy configuration, timeout
policy, and cancellation orchestration are not yet adapter APIs. The core
runtime itself already models HEAD and unsafe-method invalidation for other
Transport implementations.

The async client's header API stores one value per name. Repeated MoonCache
request fields are comma-joined; Host and Transfer-Encoding are omitted because
the client generates them. Response fields are normalized into `HeaderMap`.

## Time

The adapter does not read a system clock. The request carries `request_time`;
the real transport receives an injected `response_clock` called after the body
is read. Tests can use `MoonbitAsyncHttpTransport::fixed`.

## Example package declaration

```moonbit
import {
  "Ag108/MoonCache" @mooncache,
  "Ag108/MoonCache/adapters/async_http" @mooncache_async,
  "moonbitlang/async",
}

supported_targets = "native"
```

Inside an async function:

```moonbit
let origin = @mooncache_async.MoonbitAsyncHttpTransport::new(clock)
let runtime = @mooncache_async.AsyncCachedRuntime::new(
  @mooncache.MemoryStore::default(),
  origin,
  @mooncache.CacheOptions::private_cache(),
)
let response = runtime.execute(request, now)
```

The six adapter tests are offline and include cache hit, ETag/304, no-store,
only-if-cached, and header conversion behavior.
