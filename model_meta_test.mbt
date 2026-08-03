///|
test "request metadata normalizes method and URI boundary whitespace" {
  let request = @MoonCache.RequestMeta::new(
    " get ",
    " https://example.test/data ",
    @MoonCache.HeaderMap::new(),
    @MoonCache.Timestamp::from_seconds(10),
  )
  assert_eq(request.http_method, "GET")
  assert_eq(request.uri, "https://example.test/data")
  assert_eq(request.request_time.seconds(), 10)
}

///|
test "simple request has deterministic defaults" {
  let request = @MoonCache.RequestMeta::simple("head", "https://example.test/")
  assert_eq(request.http_method, "HEAD")
  assert_true(request.headers.is_empty())
  assert_eq(request.request_time.seconds(), 0)
}

///|
test "cache option constructors select their modes" {
  let private_options = @MoonCache.CacheOptions::private_cache()
  let shared_options = @MoonCache.CacheOptions::shared_cache()
  assert_true(private_options.mode is Private)
  assert_true(shared_options.mode is Shared)
  assert_true(private_options.allow_heuristic_freshness)
  assert_false(shared_options.allow_shared_authorized)
}

///|
test "cache mode parser is case insensitive" {
  assert_true(@MoonCache.CacheMode::from_string(" PRIVATE ") is Some(Private))
  assert_true(@MoonCache.CacheMode::from_string("shared") is Some(Shared))
  assert_eq(@MoonCache.CacheMode::from_string("other"), None)
}

///|
test "stored entry retains immutable body and timestamps" {
  let request = @MoonCache.RequestMeta::simple(
    "GET", "https://example.test/data",
  )
  let response = @MoonCache.ResponseMeta::complete(
    200,
    @MoonCache.HeaderMap::new(),
    @MoonCache.Timestamp::zero(),
    @MoonCache.Timestamp::from_seconds(1),
  )
  let entry = @MoonCache.StoredEntry::new(
    @MoonCache.PrimaryCacheKey::new("GET", request.uri),
    @MoonCache.VariantKey::empty(),
    request,
    response,
    b"body",
    @MoonCache.StoredPolicy::cacheable(
      @MoonCache.DeltaSeconds::from_seconds(60),
      false,
    ),
    @MoonCache.Timestamp::from_seconds(1),
  )
  assert_eq(entry.body_size(), 4)
  assert_eq(
    entry.touch(@MoonCache.Timestamp::from_seconds(2)).last_accessed_at.seconds(),
    2,
  )
}

///|
test "primary key labels are stable" {
  let key = @MoonCache.PrimaryCacheKey::new("get", "https://example.test/data")
  assert_eq(key.label(), "GET https://example.test/data")
}

///|
test "response completeness is explicit" {
  let response = @MoonCache.ResponseMeta::new(
    200,
    @MoonCache.HeaderMap::new(),
    @MoonCache.Timestamp::zero(),
    @MoonCache.Timestamp::zero(),
    false,
  )
  assert_false(response.body_complete)
}
