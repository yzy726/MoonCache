///|
fn async_response(
  status : Int,
  headers : Array[(String, String)],
  body : Bytes,
  request_time : Int64,
  response_time : Int64,
) -> @mooncache.TransportResponse {
  @mooncache.TransportResponse::new(
    @mooncache.ResponseMeta::complete(
      status,
      @mooncache.HeaderMap::from_pairs(headers),
      @mooncache.Timestamp::from_seconds(request_time),
      @mooncache.Timestamp::from_seconds(response_time),
    ),
    body,
  )
}

///|
struct DelayedFailureTransport {
  calls : Array[@mooncache.RuntimeRequest]
}

///|
fn DelayedFailureTransport::new() -> DelayedFailureTransport {
  DelayedFailureTransport::{ calls: [] }
}

///|
async fn DelayedFailureTransport::send(
  self : DelayedFailureTransport,
  request : @mooncache.RuntimeRequest,
) -> @mooncache.TransportResponse {
  self.calls.push(request.copy())
  @async.sleep(20)
  raise AsyncScriptedFailure("shared origin failure")
}

///|
impl AsyncTransport for DelayedFailureTransport with fn execute(self, request) {
  self.send(request)
}

///|
async test "async cached runtime misses once then serves a hit" {
  let store = @mooncache.MemoryStore::default()
  let origin = ScriptedAsyncTransport::new([
    async_response(200, [("Cache-Control", "max-age=60")], b"origin", 0L, 0L),
  ])
  let runtime = AsyncCachedRuntime::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  let request = @mooncache.RuntimeRequest::get("https://example.test/data")
  let first = runtime.execute(request, @mooncache.Timestamp::zero())
  let second = runtime.execute(request, @mooncache.Timestamp::from_seconds(10L))
  assert_true(first.source is UpstreamSource)
  assert_true(second.source is CacheSource)
  assert_eq(second.body, b"origin")
  assert_eq(origin.call_count(), 1)
}

///|
async test "async cached runtime forwards conditional ETag request" {
  let store = @mooncache.MemoryStore::default()
  let origin = ScriptedAsyncTransport::new([
    async_response(
      200,
      [("Cache-Control", "max-age=10"), ("ETag", "\"v1\"")],
      b"cached",
      0L,
      0L,
    ),
    async_response(
      304,
      [("Cache-Control", "max-age=60"), ("ETag", "\"v1\"")],
      b"",
      20L,
      20L,
    ),
  ])
  let runtime = AsyncCachedRuntime::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  let request = @mooncache.RuntimeRequest::get("https://example.test/data")
  ignore(runtime.execute(request, @mooncache.Timestamp::zero()))
  let response = runtime.execute(
    request,
    @mooncache.Timestamp::from_seconds(20L),
  )
  assert_true(response.source is RevalidatedSource)
  assert_eq(response.body, b"cached")
  assert_eq(origin.calls()[1].meta.headers.get("if-none-match"), Some("\"v1\""))
}

///|
async test "async only-if-cached miss avoids origin" {
  let store = @mooncache.MemoryStore::default()
  let origin = ScriptedAsyncTransport::new([])
  let runtime = AsyncCachedRuntime::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  let request = @mooncache.RuntimeRequest::new(
    @mooncache.RequestMeta::new(
      "GET",
      "https://example.test/data",
      @mooncache.HeaderMap::from_pairs([("Cache-Control", "only-if-cached")]),
      @mooncache.Timestamp::zero(),
    ),
    b"",
  )
  let response = runtime.execute(request, @mooncache.Timestamp::zero())
  assert_true(response.source is OnlyIfCachedSource)
  assert_eq(response.meta.status, 504)
  assert_eq(origin.call_count(), 0)
}

///|
async test "async no-store requests are never retained" {
  let store = @mooncache.MemoryStore::default()
  let origin = ScriptedAsyncTransport::new([
    async_response(200, [("Cache-Control", "max-age=60")], b"one", 0L, 0L),
    async_response(200, [("Cache-Control", "max-age=60")], b"two", 1L, 1L),
  ])
  let runtime = AsyncCachedRuntime::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  let request = @mooncache.RuntimeRequest::new(
    @mooncache.RequestMeta::new(
      "GET",
      "https://example.test/data",
      @mooncache.HeaderMap::from_pairs([("Cache-Control", "no-store")]),
      @mooncache.Timestamp::zero(),
    ),
    b"",
  )
  let first = runtime.execute(request, @mooncache.Timestamp::zero())
  let second = runtime.execute(request, @mooncache.Timestamp::from_seconds(1L))
  assert_eq(first.body, b"one")
  assert_eq(second.body, b"two")
  assert_eq(origin.call_count(), 2)
  assert_eq(runtime.store_stats().entries, 0)
}

///|
test "async HTTP header bridge joins repeated request fields" {
  let headers = @mooncache.HeaderMap::from_pairs([
    ("Accept", "text/plain"),
    ("Accept", "application/json"),
    ("Host", "ignored.example"),
    ("Transfer-Encoding", "chunked"),
  ])
  let converted = headers_to_async_http(headers)
  assert_eq(converted.get("accept"), Some("text/plain, application/json"))
  assert_false(converted.contains("host"))
  assert_false(converted.contains("transfer-encoding"))
}

///|
test "async HTTP response header bridge normalizes names" {
  let converted = headers_from_async_http(
    Map([("Cache-Control", "max-age=60"), ("ETag", "\"v1\"")]),
  )
  assert_eq(converted.get("cache-control"), Some("max-age=60"))
  assert_eq(converted.get("etag"), Some("\"v1\""))
}

///|
async test "cached client GET uses its injected clock and caches the result" {
  let store = @mooncache.MemoryStore::default()
  let origin = ScriptedAsyncTransport::new([
    async_response(200, [("Cache-Control", "max-age=60")], b"cached", 7L, 7L),
  ])
  let client = CachedClient::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
    clock=() => @mooncache.Timestamp::from_seconds(7L),
  )
  let first = client.get("https://example.test/data")
  let second = client.get("https://example.test/data")
  assert_true(first.source is UpstreamSource)
  assert_true(second.source is CacheSource)
  assert_eq(second.body, b"cached")
  assert_eq(origin.call_count(), 1)
}

///|
async test "cached client HEAD reuses a cached GET without returning its body" {
  let store = @mooncache.MemoryStore::default()
  let origin = ScriptedAsyncTransport::new([
    async_response(200, [("Cache-Control", "max-age=60")], b"entity", 0L, 0L),
  ])
  let client = CachedClient::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  ignore(client.get("https://example.test/data"))
  let response = client.head("https://example.test/data")
  assert_true(response.source is CacheSource)
  assert_eq(response.body, b"")
  assert_eq(origin.call_count(), 1)
}

///|
async test "async runtime rejects an oversized body before storing it" {
  let store = @mooncache.MemoryStore::default()
  let origin = ScriptedAsyncTransport::new([
    async_response(200, [("Cache-Control", "max-age=60")], b"12345", 0L, 0L),
  ])
  let runtime = AsyncCachedRuntime::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  ).with_body_limit(4)
  let mut rejected = false
  try
    runtime.execute(
      @mooncache.RuntimeRequest::get("https://example.test/large"),
      @mooncache.Timestamp::zero(),
    )
  catch {
    AsyncBodyTooLarge(actual~, maximum~) => {
      assert_eq(actual, 5)
      assert_eq(maximum, 4)
      rejected = true
    }
    error => raise error
  } noraise {
    _ => ()
  }
  assert_true(rejected)
  assert_eq(store.stats().entries, 0)
}

///|
async test "cached client maps its configured deadline to a stable error" {
  let store = @mooncache.MemoryStore::default()
  let origin = ScriptedAsyncTransport::with_outcomes([
    AsyncTransportDelayed(
      50,
      async_response(200, [("Cache-Control", "max-age=60")], b"late", 0L, 0L),
    ),
  ])
  let options = CachedClientOptions::default().with_timeout(1)
  let client = CachedClient::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
    client_options=options,
  )
  let mut timed_out = false
  try client.get("https://example.test/slow") catch {
    AsyncRequestTimedOut(1) => timed_out = true
    error => raise error
  } noraise {
    _ => ()
  }
  assert_true(timed_out)
  assert_eq(store.stats().entries, 0)
}

///|
async test "scripted async origin propagates failures without storing" {
  let store = @mooncache.MemoryStore::default()
  let origin = ScriptedAsyncTransport::with_outcomes([
    AsyncTransportFailure("connection refused"),
  ])
  let client = CachedClient::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  let mut failed = false
  try client.get("https://example.test/failure") catch {
    AsyncScriptedFailure("connection refused") => failed = true
    error => raise error
  } noraise {
    _ => ()
  }
  assert_true(failed)
  assert_eq(store.stats().entries, 0)
}

///|
async test "same-origin redirects retain separate cache keys" {
  let store = @mooncache.MemoryStore::default()
  let origin = ScriptedAsyncTransport::new([
    async_response(
      302,
      [("Cache-Control", "max-age=60"), ("Location", "/final")],
      b"",
      0L,
      0L,
    ),
    async_response(200, [("Cache-Control", "max-age=60")], b"final", 0L, 0L),
  ])
  let options = CachedClientOptions::default().with_redirects(
    FollowSameOrigin,
    3,
  )
  let client = CachedClient::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
    client_options=options,
  )
  let first = client.get("https://example.test/start")
  let second = client.get("https://example.test/start")
  assert_eq(first.body, b"final")
  assert_eq(second.body, b"final")
  assert_eq(origin.call_count(), 2)
  assert_eq(store.variant_count("https://example.test/start"), 1)
  assert_eq(store.variant_count("https://example.test/final"), 1)
}

///|
async test "same-origin redirect policy rejects a cross-origin target" {
  let store = @mooncache.MemoryStore::default()
  let origin = ScriptedAsyncTransport::new([
    async_response(
      302,
      [("Location", "https://other.test/private")],
      b"",
      0L,
      0L,
    ),
  ])
  let options = CachedClientOptions::default().with_redirects(
    FollowSameOrigin,
    3,
  )
  let client = CachedClient::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
    client_options=options,
  )
  let mut rejected = false
  try client.get("https://example.test/start") catch {
    AsyncRedirectRejected("https://other.test/private") => rejected = true
    error => raise error
  } noraise {
    _ => ()
  }
  assert_true(rejected)
  assert_eq(origin.call_count(), 1)
}

///|
test "coalescing keys hash all request headers and skip unsafe reuse" {
  let english = @mooncache.RuntimeRequest::get("HTTPS://EXAMPLE.TEST:443/data").with_headers(
    @mooncache.HeaderMap::from_pairs([
      ("Accept-Language", "en"),
      ("Authorization", "Bearer secret"),
    ]),
  )
  let chinese = @mooncache.RuntimeRequest::get("https://example.test/data").with_headers(
    @mooncache.HeaderMap::from_pairs([
      ("Accept-Language", "zh"),
      ("Authorization", "Bearer secret"),
    ]),
  )
  let english_key = request_coalescing_key(english).unwrap()
  let chinese_key = request_coalescing_key(chinese).unwrap()
  assert_false(english_key == chinese_key)
  assert_eq(english_key.length(), 64)
  assert_false(english_key.contains("secret"))
  assert_true(
    request_coalescing_key(
      english.with_headers(
        @mooncache.HeaderMap::from_pairs([("Cache-Control", "no-store")]),
      ),
    )
    is None,
  )
  assert_true(
    request_coalescing_key(
      english.with_headers(
        @mooncache.HeaderMap::from_pairs([("Range", "bytes=0-9")]),
      ),
    )
    is None,
  )
}

///|
async test "twenty concurrent cached GETs use one upstream request" {
  let store = @mooncache.MemoryStore::default()
  let origin = ScriptedAsyncTransport::with_outcomes([
    AsyncTransportDelayed(
      30,
      async_response(200, [("Cache-Control", "max-age=60")], b"shared", 0L, 0L),
    ),
  ])
  let client = CachedClient::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  let responses : Array[@mooncache.RuntimeResponse] = []
  @async.with_task_group() <| tasks => {
    for _ in 0..<20 {
      tasks.spawn_bg() <| () => {
        responses.push(client.get("https://example.test/coalesced"))
      }
    }
  }
  assert_eq(origin.call_count(), 1)
  assert_eq(responses.length(), 20)
  assert_true(responses.all(fn(response) { response.body == b"shared" }))
  let mut joined = 0
  for response in responses {
    if response.trace.has_reason(RuntimeCoalesced) {
      joined = joined + 1
    }
  }
  assert_eq(joined, 19)
  let stats = client.coalescing_stats()
  assert_eq(stats.started, 1)
  assert_eq(stats.coalesced, 19)
  assert_eq(stats.active_flights, 0)
  assert_eq(store.stats().entries, 1)
}

///|
async test "different Vary candidates never share an upstream flight" {
  let store = @mooncache.MemoryStore::default()
  let vary_headers = [
    ("Cache-Control", "max-age=60"),
    ("Vary", "Accept-Language"),
  ]
  let origin = ScriptedAsyncTransport::with_outcomes([
    AsyncTransportDelayed(
      20,
      async_response(200, vary_headers, b"first", 0L, 0L),
    ),
    AsyncTransportDelayed(
      20,
      async_response(200, vary_headers, b"second", 0L, 0L),
    ),
  ])
  let client = CachedClient::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  @async.with_task_group() <| tasks => {
    for language in ["en", "zh"] {
      tasks.spawn_bg() <| () => {
        ignore(
          client.get(
            "https://example.test/language",
            headers=@mooncache.HeaderMap::from_pairs([
              ("Accept-Language", language),
            ]),
          ),
        )
      }
    }
  }
  assert_eq(origin.call_count(), 2)
  assert_eq(store.variant_count("https://example.test/language"), 2)
  assert_eq(client.coalescing_stats().coalesced, 0)
}

///|
async test "all coalesced waiters receive the same upstream failure" {
  let store = @mooncache.MemoryStore::default()
  let origin = DelayedFailureTransport::new()
  let client = CachedClient::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  let failures = [0]
  @async.with_task_group() <| tasks => {
    for _ in 0..<8 {
      tasks.spawn_bg(allow_failure=true) <| () => {
        try client.get("https://example.test/failure") |> ignore catch {
          AsyncScriptedFailure("shared origin failure") =>
            failures[0] = failures[0] + 1
          error => raise error
        }
      }
    }
  }
  assert_eq(origin.calls.length(), 1)
  assert_eq(failures[0], 8)
  assert_eq(store.stats().entries, 0)
  assert_eq(client.coalescing_stats().failed, 1)
  assert_eq(client.coalescing_stats().active_flights, 0)
}

///|
async test "cancelling a flight leader still delivers to its follower" {
  let store = @mooncache.MemoryStore::default()
  let origin = ScriptedAsyncTransport::with_outcomes([
    AsyncTransportDelayed(
      30,
      async_response(
        200,
        [("Cache-Control", "max-age=60")],
        b"completed",
        0L,
        0L,
      ),
    ),
  ])
  let client = CachedClient::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  let leader_cancelled = [false]
  let follower_body = [b""]
  @async.with_task_group() <| tasks => {
    let leader = tasks.spawn(allow_failure=true) <| () => {
      try client.get("https://example.test/cancel") |> ignore catch {
        error if @async.is_cancellation_error(error) => {
          leader_cancelled[0] = true
          raise error
        }
        error => raise error
      }
    }
    @async.sleep(2)
    tasks.spawn_bg() <| () => {
      follower_body[0] = client.get("https://example.test/cancel").body
    }
    @async.sleep(2)
    leader.cancel()
  }
  assert_true(leader_cancelled[0])
  assert_eq(follower_body[0], b"completed")
  assert_eq(origin.call_count(), 1)
  assert_eq(client.coalescing_stats().active_flights, 0)
}

///|
async test "real async HTTP transport caches a local server response" {
  let origin_calls = [0]
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever() <| ((request, body, connection) => {
        while body.read_some() is Some(_) {

        }
        origin_calls[0] = origin_calls[0] + 1
        connection.send_response(
          200,
          "OK",
          extra_headers=Map([("Cache-Control", "max-age=60")]),
        )
        if !(request.meth is Head) {
          connection.write_string("local")
        }
      })
    }
    let uri = "http://localhost:\{server.addr.port()}/data"
    let store = @mooncache.MemoryStore::default()
    let transport = MoonbitAsyncHttpTransport::fixed(
      @mooncache.Timestamp::zero(),
    )
    let client = CachedClient::new(
      store,
      transport,
      @mooncache.CacheOptions::private_cache(),
    )
    let first = client.get(uri)
    let second = client.get(uri)
    assert_eq(first.body, b"local")
    assert_true(second.source is CacheSource)
    assert_eq(origin_calls[0], 1)
  }
}
