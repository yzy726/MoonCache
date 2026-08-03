///|
test "store put result labels are stable" {
  assert_eq(@MoonCache.StoreInserted.label(), "INSERTED")
  assert_eq(@MoonCache.StoreReplacedResult.label(), "REPLACED")
  assert_eq(@MoonCache.StoreRejectedNoStore.label(), "REJECTED_NO_STORE")
  assert_true(@MoonCache.StoreInserted.accepted())
  assert_true(@MoonCache.StoreReplacedResult.accepted())
  assert_false(@MoonCache.StoreRejectedCapacity.accepted())
}

///|
test "store stats calculates deterministic hit ratio" {
  let store = @MoonCache.MemoryStore::default()
  let key = @MoonCache.PrimaryCacheKey::new("GET", "https://example.test/data")
  ignore(store.find_variants(key))
  ignore(
    store.put(policy_entry([], [("Cache-Control", "max-age=60")], b"x", 0)),
  )
  ignore(store.find_variants(key))
  let stats = store.stats()
  assert_eq(stats.requests(), 2L)
  assert_eq(stats.hit_rate_per_mille(), 500)
  assert_eq(stats.saved_origin_requests(), 1L)
}

///|
test "empty store stats report as empty" {
  let stats = @MoonCache.MemoryStore::default().stats()
  assert_true(stats.is_empty())
  assert_eq(stats.hit_rate_per_mille(), 0)
}

///|
test "store stats JSON contains every operational counter" {
  let report = @MoonCache.MemoryStore::default().stats().json_report()
  assert_true(report.contains("\"entries\": 0"))
  assert_true(report.contains("\"hit_rate_per_mille\": 0"))
  assert_true(report.contains("\"invalidated_entries\": 0"))
  assert_true(report.contains("\"rejected_entries\": 0"))
}

///|
test "store stats text report is human readable" {
  let report = @MoonCache.MemoryStore::default().stats().text_report()
  assert_true(report.contains("Entries: 0"))
  assert_true(report.contains("Hit rate: 0/1000"))
}

///|
test "runtime response JSON excludes body and redacts credentials" {
  let headers = @MoonCache.HeaderMap::from_pairs([
    ("Content-Type", "text/plain"),
    ("Set-Cookie", "session=secret"),
  ])
  let response = @MoonCache.RuntimeResponse::{
    meta: @MoonCache.ResponseMeta::complete(
      200,
      headers,
      @MoonCache.Timestamp::zero(),
      @MoonCache.Timestamp::zero(),
    ),
    body: b"secret response body",
    source: CacheSource,
    trace: @MoonCache.CacheTrace::new(ServeFresh),
  }
  let report = response.json_report()
  assert_true(response.is_cache_reuse())
  assert_true(report.contains("\"body_bytes\": 20"))
  assert_true(report.contains("<redacted>"))
  assert_false(report.contains("session=secret"))
  assert_false(report.contains("secret response body"))
}

///|
test "upstream response is not classified as cache reuse" {
  let response = @MoonCache.RuntimeResponse::{
    meta: @MoonCache.ResponseMeta::complete(
      200,
      @MoonCache.HeaderMap::new(),
      @MoonCache.Timestamp::zero(),
      @MoonCache.Timestamp::zero(),
    ),
    body: b"",
    source: UpstreamSource,
    trace: @MoonCache.CacheTrace::new(Fetch),
  }
  assert_false(response.is_cache_reuse())
}

///|
test "runtime text report combines source metadata and trace" {
  let response = @MoonCache.RuntimeResponse::{
    meta: @MoonCache.ResponseMeta::complete(
      504,
      @MoonCache.HeaderMap::from_pairs([("Content-Length", "0")]),
      @MoonCache.Timestamp::zero(),
      @MoonCache.Timestamp::zero(),
    ),
    body: b"",
    source: OnlyIfCachedSource,
    trace: @MoonCache.CacheTrace::new(OnlyIfCachedMiss),
  }
  let report = response.text_report()
  assert_true(report.contains("Source: only-if-cached"))
  assert_true(report.contains("Status: 504"))
  assert_true(report.contains("Decision: ONLY_IF_CACHED_MISS"))
}
