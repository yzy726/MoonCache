///|
struct RecordingCacheObserver {
  events : Array[@MoonCache.CacheEvent]
}

///|
fn RecordingCacheObserver::new() -> RecordingCacheObserver {
  RecordingCacheObserver::{ events: [] }
}

///|
impl @MoonCache.CacheObserver for RecordingCacheObserver with fn observe(
  self,
  event,
) {
  self.events.push(event)
}

///|
fn observer_response(
  status : Int,
  headers : Array[(String, String)],
  body : Bytes,
  request_time : Int64,
  response_time : Int64,
) -> @MoonCache.TransportResponse {
  @MoonCache.TransportResponse::new(
    @MoonCache.ResponseMeta::complete(
      status,
      @MoonCache.HeaderMap::from_pairs(headers),
      @MoonCache.Timestamp::from_seconds(request_time),
      @MoonCache.Timestamp::from_seconds(response_time),
    ),
    body,
  )
}

///|
test "cache stats accumulator covers every terminal metric" {
  let stats = @MoonCache.CacheStats::new()
  let request = @MoonCache.RequestMeta::simple(
    "GET", "https://example.test/data",
  )
  let events = [
    @MoonCache.CacheEvent::new(CacheRequestCompleted, request),
    @MoonCache.CacheEvent::new(CacheHit, request),
    @MoonCache.CacheEvent::new(CacheMiss, request),
    @MoonCache.CacheEvent::new(CacheBypass, request),
    @MoonCache.CacheEvent::new(CacheStored, request),
    @MoonCache.CacheEvent::new(
      CacheRevalidated,
      request,
      duration_milliseconds=250L,
    ),
    @MoonCache.CacheEvent::new(CacheNotModified, request),
    @MoonCache.CacheEvent::new(CacheStaleServed, request),
    @MoonCache.CacheEvent::new(CacheUpstreamFetched, request),
    @MoonCache.CacheEvent::new(CacheUpstreamError, request),
    @MoonCache.CacheEvent::new(CacheEvicted, request, count=2L),
    @MoonCache.CacheEvent::new(CachePurged, request, count=3L),
    @MoonCache.CacheEvent::new(CacheCoalesced, request, count=4L),
    @MoonCache.CacheEvent::new(CacheBytesSaved, request, body_bytes=512L),
    @MoonCache.CacheEvent::new(CacheUpstreamRequestSaved, request, count=5L),
    @MoonCache.CacheEvent::new(CacheBackgroundRevalidation, request),
    @MoonCache.CacheEvent::new(CacheBackgroundFailure, request),
  ]
  for event in events {
    @MoonCache.CacheObserver::observe(stats, event)
  }
  let snapshot = stats.snapshot()
  assert_eq(snapshot.requests, 1L)
  assert_eq(snapshot.hits, 1L)
  assert_eq(snapshot.misses, 1L)
  assert_eq(snapshot.bypasses, 1L)
  assert_eq(snapshot.stores, 1L)
  assert_eq(snapshot.revalidations, 1L)
  assert_eq(snapshot.not_modified, 1L)
  assert_eq(snapshot.stale_served, 1L)
  assert_eq(snapshot.upstream_fetches, 1L)
  assert_eq(snapshot.upstream_errors, 1L)
  assert_eq(snapshot.evictions, 2L)
  assert_eq(snapshot.purges, 1L)
  assert_eq(snapshot.purged_entries, 3L)
  assert_eq(snapshot.coalesced_requests, 4L)
  assert_eq(snapshot.saved_bytes, 512L)
  assert_eq(snapshot.saved_upstream_requests, 5L)
  assert_eq(snapshot.average_validation_milliseconds, 250L)
  assert_eq(snapshot.background_revalidations, 1L)
  assert_eq(snapshot.background_failures, 1L)
  assert_eq(snapshot.hit_rate_per_mille(), 333)
}

///|
test "cache stats reports and coalesced reconciliation are deterministic" {
  let base = @MoonCache.CacheStats::new().snapshot()
  let snapshot = base.with_coalesced_total(7L)
  assert_eq(snapshot.coalesced_requests, 7L)
  assert_eq(snapshot.saved_upstream_requests, 7L)
  let json = snapshot.json_report()
  let text = snapshot.text_report()
  assert_true(json.contains("\"coalesced_requests\": 7"))
  assert_true(json.contains("\"average_validation_milliseconds\": 0"))
  assert_true(text.contains("Coalesced requests: 7"))
  assert_true(text.contains("Average validation: 0ms"))
}

///|
test "cached runtime emits observer events and complete snapshots" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.FakeTransport::new([
    observer_response(
      200,
      [("Cache-Control", "max-age=0"), ("ETag", "\"v1\"")],
      b"payload",
      0L,
      0L,
    ),
    observer_response(
      304,
      [("Cache-Control", "max-age=60"), ("ETag", "\"v1\"")],
      b"",
      10L,
      12L,
    ),
  ])
  let observer = RecordingCacheObserver::new()
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    @MoonCache.CacheOptions::private_cache(),
  ).with_observer(observer)
  let uri = "https://example.test/observed"
  ignore(
    runtime.execute(
      @MoonCache.RuntimeRequest::get(uri),
      @MoonCache.Timestamp::zero(),
    ),
  )
  ignore(
    runtime.execute(
      @MoonCache.RuntimeRequest::get(uri).with_request_time(
        @MoonCache.Timestamp::from_seconds(10L),
      ),
      @MoonCache.Timestamp::from_seconds(12L),
    ),
  )
  ignore(
    runtime.execute(
      @MoonCache.RuntimeRequest::get(uri).with_request_time(
        @MoonCache.Timestamp::from_seconds(15L),
      ),
      @MoonCache.Timestamp::from_seconds(15L),
    ),
  )
  assert_eq(runtime.purge(uri), 1)
  let snapshot = runtime.stats_snapshot()
  assert_eq(snapshot.requests, 3L)
  assert_eq(snapshot.hits, 2L)
  assert_eq(snapshot.misses, 1L)
  assert_eq(snapshot.stores, 2L)
  assert_eq(snapshot.revalidations, 1L)
  assert_eq(snapshot.not_modified, 1L)
  assert_eq(snapshot.upstream_fetches, 2L)
  assert_eq(snapshot.saved_bytes, 14L)
  assert_eq(snapshot.saved_upstream_requests, 1L)
  assert_eq(snapshot.average_validation_milliseconds, 2_000L)
  assert_eq(snapshot.purges, 1L)
  assert_eq(snapshot.purged_entries, 1L)
  assert_true(observer.events.any(fn(event) { event.kind is CacheNotModified }))
  assert_true(observer.events.any(fn(event) { event.kind is CachePurged }))
  assert_false(
    observer.events.any(fn(event) {
      event.body_bytes > 0L && event.detail is Some(_)
    }),
  )
}

///|
test "cached runtime records upstream errors that do not return a response" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.FakeTransport::with_outcomes([
    TransportFailure("connection refused"),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    @MoonCache.CacheOptions::private_cache(),
  )
  try
    runtime.execute(
      @MoonCache.RuntimeRequest::get("https://example.test/error"),
      @MoonCache.Timestamp::zero(),
    )
    |> ignore
  catch {
    @MoonCache.RuntimeTransportFailure("connection refused") => ()
    error => raise error
  }
  let snapshot = runtime.stats_snapshot()
  assert_eq(snapshot.requests, 1L)
  assert_eq(snapshot.upstream_fetches, 1L)
  assert_eq(snapshot.upstream_errors, 1L)
}

///|
test "runtime telemetry observes store eviction deltas" {
  let store = @MoonCache.MemoryStore::new(
    @MoonCache.MemoryStoreOptions::default().with_entry_limit(1),
  )
  let transport = @MoonCache.FakeTransport::new([
    observer_response(200, [("Cache-Control", "max-age=60")], b"one", 0L, 0L),
    observer_response(200, [("Cache-Control", "max-age=60")], b"two", 0L, 0L),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    @MoonCache.CacheOptions::private_cache(),
  )
  ignore(
    runtime.execute(
      @MoonCache.RuntimeRequest::get("https://example.test/one"),
      @MoonCache.Timestamp::zero(),
    ),
  )
  ignore(
    runtime.execute(
      @MoonCache.RuntimeRequest::get("https://example.test/two"),
      @MoonCache.Timestamp::zero(),
    ),
  )
  assert_eq(runtime.stats_snapshot().evictions, 1L)
}
