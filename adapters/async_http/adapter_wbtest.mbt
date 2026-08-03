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
