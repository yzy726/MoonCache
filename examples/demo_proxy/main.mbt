///|
async fn demo() -> Unit {
  println("demo_proxy")
  println("upstream: scripted recording transport (no real network)")
  let origin = @mooncache.RecordingTransport::with_outcomes([
    @mooncache.TransportSuccess(
      @support.response(
        200,
        [
          ("Cache-Control", "max-age=10, stale-if-error=3600"),
          ("ETag", "\"demo-v1\""),
          ("Vary", "Accept-Language"),
        ],
        b"demo payload",
        0L,
        0L,
      ),
    ),
    @mooncache.TransportSuccess(
      @support.response(304, [("ETag", "\"demo-v1\"")], b"", 20L, 20L),
    ),
    @mooncache.TransportFailure("connection refused"),
    @mooncache.TransportSuccess(
      @support.response(
        200,
        [
          ("Cache-Control", "max-age=10, stale-if-error=3600"),
          ("Vary", "Accept-Language"),
        ],
        b"demo payload (zh)",
        101L,
        101L,
      ),
    ),
    @mooncache.TransportSuccess(
      @support.response(
        200,
        [("Cache-Control", "max-age=60")],
        b"burst payload",
        102L,
        102L,
      ),
    ),
  ])
  let store = @mooncache.MemoryStore::default()
  let runtime = @mooncache.CachedRuntime::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  let request = @mooncache.RuntimeRequest::get("https://example.test/demo")
  let first = runtime.execute(request.copy(), @mooncache.Timestamp::zero())
  @support.print_result("1. first request", first)
  let second = runtime.execute(
    request.copy(),
    @mooncache.Timestamp::from_seconds(5L),
  )
  @support.print_result("2. second request", second)
  let third = runtime.execute(
    request.copy(),
    @mooncache.Timestamp::from_seconds(20L),
  )
  @support.print_result("3. after expiry", third)
  let conditional = origin.calls()[1].meta.headers.get("if-none-match")
  println("   If-None-Match: \{conditional.unwrap_or("<missing>")}")
  let fourth = runtime.execute(
    request.copy(),
    @mooncache.Timestamp::from_seconds(100L),
  )
  @support.print_result("4. upstream down", fourth)
  let language_headers = @mooncache.HeaderMap::new()
  ignore(language_headers.append("Accept-Language", "zh"))
  let language_request = @mooncache.RuntimeRequest::get(
    "https://example.test/demo",
  ).with_headers(language_headers)
  let fifth = runtime.execute(
    language_request,
    @mooncache.Timestamp::from_seconds(101L),
  )
  @support.print_result("5. new language variant", fifth)
  @support.require(first.source is UpstreamSource, "step 1 must MISS")
  @support.require(second.source is CacheSource, "step 2 must HIT")
  @support.require(third.source is RevalidatedSource, "step 3 must REVALIDATE")
  @support.require(
    conditional == Some("\"demo-v1\""),
    "revalidation must send If-None-Match",
  )
  @support.require(
    third.body == b"demo payload",
    "304 must retain the cached body",
  )
  @support.require(fourth.source is StaleSource, "step 4 must STALE-IF-ERROR")
  @support.require(
    fourth.body == b"demo payload",
    "stale response must reuse the cached body",
  )
  @support.require(fifth.source is UpstreamSource, "step 5 must VARY MISS")
  @support.require(fifth.body == b"demo payload (zh)", "zh variant body")
  let group = @concurrency.RequestGroup::new(fn(
    response : @mooncache.RuntimeResponse,
  ) {
    response.copy()
  })
  let burst_request = @mooncache.RuntimeRequest::get(
    "https://example.test/burst",
  )
  let burst_time = @mooncache.Timestamp::from_seconds(102L)
  let bodies : Array[Bytes] = []
  @async.with_task_group() <| tasks => {
    for _ in 0..<20 {
      tasks.spawn_bg() <| () => {
        let result = group.run("burst", () => {
          runtime.execute(burst_request.copy(), burst_time)
        })
        bodies.push(result.value.body)
      }
    }
  }
  println(
    "6. twenty concurrent requests -> upstream calls: \{origin.call_count()} total",
  )
  println("   coalesced: \{group.stats().coalesced}")
  @support.require(bodies.length() == 20, "all twenty waiters get a response")
  @support.require(
    bodies.all(fn(body) { body == b"burst payload" }),
    "every waiter sees the shared payload",
  )
  @support.require(group.stats().started == 1L, "one shared upstream flight")
  @support.require(
    group.stats().coalesced == 19L,
    "nineteen requests are coalesced",
  )
  println("demo complete")
}

///|
fn main {
  @async.run_async_main(demo)
}
