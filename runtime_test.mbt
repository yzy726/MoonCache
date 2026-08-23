///|
test "runtime miss fetches then stores for next hit" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.FakeTransport::new([
    scripted_response(200, [("Cache-Control", "max-age=60")], b"origin", 0, 0),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let request = @MoonCache.RuntimeRequest::get("https://example.test/data")
  let first = try! runtime.execute(request, @MoonCache.Timestamp::zero())
  let second = try! runtime.execute(
    request,
    @MoonCache.Timestamp::from_seconds(10),
  )
  assert_true(first.source is UpstreamSource)
  assert_true(second.source is CacheSource)
  assert_eq(second.body, b"origin")
  assert_eq(transport.call_count(), 1)
  assert_eq(store.stats().entries, 1)
}

///|
test "runtime keeps independent Vary language responses" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.FakeTransport::new([
    scripted_response(
      200,
      [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
      b"english",
      0,
      0,
    ),
    scripted_response(
      200,
      [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
      b"chinese",
      0,
      1,
    ),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let english = @MoonCache.RuntimeRequest::new(
    policy_request("GET", [("Accept-Language", "en")]),
    b"",
  )
  let chinese = @MoonCache.RuntimeRequest::new(
    policy_request("GET", [("Accept-Language", "zh")]),
    b"",
  )
  assert_eq(
    (try! runtime.execute(english, @MoonCache.Timestamp::zero())).body,
    b"english",
  )
  assert_eq(
    (try! runtime.execute(chinese, @MoonCache.Timestamp::from_seconds(1))).body,
    b"chinese",
  )
  let hit = try! runtime.execute(english, @MoonCache.Timestamp::from_seconds(2))
  assert_eq(hit.body, b"english")
  assert_true(hit.source is CacheSource)
  assert_eq(transport.call_count(), 2)
}

///|
test "runtime stale ETag sends conditional request and merges 304" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.RecordingTransport::new([
    scripted_response(
      200,
      [("Cache-Control", "max-age=10"), ("ETag", "\"v1\"")],
      b"cached body",
      0,
      0,
    ),
    scripted_response(
      304,
      [("Cache-Control", "max-age=60"), ("ETag", "\"v1\"")],
      b"",
      20,
      20,
    ),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let request = @MoonCache.RuntimeRequest::get("https://example.test/data")
  ignore(try! runtime.execute(request, @MoonCache.Timestamp::zero()))
  let response = try! runtime.execute(
    request,
    @MoonCache.Timestamp::from_seconds(20),
  )
  assert_true(response.source is RevalidatedSource)
  assert_eq(response.body, b"cached body")
  assert_eq(
    transport.calls()[1].meta.headers.get("if-none-match"),
    Some("\"v1\""),
  )
  assert_true(response.trace.generated_headers.contains("if-none-match"))
}

///|
test "runtime modified revalidation replaces cached response" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.FakeTransport::new([
    scripted_response(
      200,
      [("Cache-Control", "max-age=10"), ("ETag", "\"v1\"")],
      b"old",
      0,
      0,
    ),
    scripted_response(
      200,
      [("Cache-Control", "max-age=60"), ("ETag", "\"v2\"")],
      b"new",
      20,
      20,
    ),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let request = @MoonCache.RuntimeRequest::get("https://example.test/data")
  ignore(try! runtime.execute(request, @MoonCache.Timestamp::zero()))
  let changed = try! runtime.execute(
    request,
    @MoonCache.Timestamp::from_seconds(20),
  )
  let hit = try! runtime.execute(
    request,
    @MoonCache.Timestamp::from_seconds(21),
  )
  assert_true(changed.source is RevalidatedSource)
  assert_eq(changed.body, b"new")
  assert_true(hit.source is CacheSource)
  assert_eq(hit.body, b"new")
  assert_eq(transport.call_count(), 2)
}

///|
test "runtime only-if-cached miss returns synthetic 504" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.FakeTransport::new([])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let request = @MoonCache.RuntimeRequest::new(
    policy_request("GET", [("Cache-Control", "only-if-cached")]),
    b"",
  )
  let response = try! runtime.execute(request, @MoonCache.Timestamp::zero())
  assert_eq(response.meta.status, 504)
  assert_true(response.source is OnlyIfCachedSource)
  assert_eq(transport.call_count(), 0)
}

///|
test "runtime request no-store bypasses lookup and storage" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.FakeTransport::new([
    scripted_response(200, [("Cache-Control", "max-age=60")], b"one", 0, 0),
    scripted_response(200, [("Cache-Control", "max-age=60")], b"two", 1, 1),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let request = @MoonCache.RuntimeRequest::new(
    policy_request("GET", [("Cache-Control", "no-store")]),
    b"",
  )
  let first = try! runtime.execute(request, @MoonCache.Timestamp::zero())
  let second = try! runtime.execute(
    request,
    @MoonCache.Timestamp::from_seconds(1),
  )
  assert_eq(first.body, b"one")
  assert_eq(second.body, b"two")
  assert_true(first.trace.action is Bypass)
  assert_eq(store.stats().entries, 0)
  assert_eq(transport.call_count(), 2)
}

///|
test "runtime response no-store is never retained" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.FakeTransport::new([
    scripted_response(200, [("Cache-Control", "no-store")], b"one", 0, 0),
    scripted_response(200, [("Cache-Control", "no-store")], b"two", 1, 1),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let request = @MoonCache.RuntimeRequest::get("https://example.test/data")
  ignore(try! runtime.execute(request, @MoonCache.Timestamp::zero()))
  let second = try! runtime.execute(
    request,
    @MoonCache.Timestamp::from_seconds(1),
  )
  assert_eq(second.body, b"two")
  assert_eq(transport.call_count(), 2)
  assert_eq(store.stats().entries, 0)
}

///|
test "runtime HEAD can reuse GET metadata without body" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.FakeTransport::new([
    scripted_response(
      200,
      [("Cache-Control", "max-age=60"), ("Content-Length", "4")],
      b"body",
      0,
      0,
    ),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  ignore(
    try! runtime.execute(
      @MoonCache.RuntimeRequest::get("https://example.test/data"),
      @MoonCache.Timestamp::zero(),
    ),
  )
  let head = @MoonCache.RuntimeRequest::new(
    @MoonCache.RequestMeta::simple("HEAD", "https://example.test/data"),
    b"",
  )
  let response = try! runtime.execute(
    head,
    @MoonCache.Timestamp::from_seconds(1),
  )
  assert_true(response.source is CacheSource)
  assert_eq(response.body, b"")
  assert_eq(response.meta.headers.get("content-length"), Some("4"))
}

///|
test "runtime unsafe method invalidates existing variants" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.FakeTransport::new([
    scripted_response(200, [("Cache-Control", "max-age=60")], b"old", 0, 0),
    scripted_response(204, [], b"", 1, 1),
    scripted_response(200, [("Cache-Control", "max-age=60")], b"new", 2, 2),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let get = @MoonCache.RuntimeRequest::get("https://example.test/data")
  ignore(try! runtime.execute(get, @MoonCache.Timestamp::zero()))
  let post = @MoonCache.RuntimeRequest::new(
    @MoonCache.RequestMeta::simple("POST", "https://example.test/data"),
    b"update",
  )
  ignore(try! runtime.execute(post, @MoonCache.Timestamp::from_seconds(1)))
  let refreshed = try! runtime.execute(
    get,
    @MoonCache.Timestamp::from_seconds(2),
  )
  assert_eq(refreshed.body, b"new")
  assert_eq(transport.call_count(), 3)
}

///|
test "runtime store body limit does not block upstream response" {
  let store = @MoonCache.MemoryStore::new(
    @MoonCache.MemoryStoreOptions::with_limits(10, 100, 3),
  )
  let transport = @MoonCache.FakeTransport::new([
    scripted_response(200, [("Cache-Control", "max-age=60")], b"large", 0, 0),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let response = try! runtime.execute(
    @MoonCache.RuntimeRequest::get("https://example.test/data"),
    @MoonCache.Timestamp::zero(),
  )
  assert_eq(response.body, b"large")
  assert_eq(store.stats().entries, 0)
  assert_true(response.trace.has_reason(RuntimeNotStored))
}

///|
test "runtime malformed URI bypasses cache" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.FakeTransport::new([
    scripted_response(200, [("Cache-Control", "max-age=60")], b"body", 0, 0),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let response = try! runtime.execute(
    @MoonCache.RuntimeRequest::get("/relative"),
    @MoonCache.Timestamp::zero(),
  )
  assert_true(response.source is UpstreamSource)
  assert_eq(store.stats().entries, 0)
}

///|
test "runtime propagates scripted transport failure" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.FakeTransport::with_outcomes([
    TransportFailure("origin unavailable"),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let result : Result[@MoonCache.RuntimeResponse, @MoonCache.RuntimeError] = Ok(
    runtime.execute(
      @MoonCache.RuntimeRequest::get("https://example.test/data"),
      @MoonCache.Timestamp::zero(),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(RuntimeTransportFailure("origin unavailable")))
}

///|
test "runtime max-stale serves cache without origin call" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry([], [("Cache-Control", "max-age=10")], b"stale", 0)
  ignore(store.put(entry))
  let transport = @MoonCache.FakeTransport::new([])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let request = @MoonCache.RuntimeRequest::new(
    policy_request("GET", [("Cache-Control", "max-stale=20")]),
    b"",
  )
  let response = try! runtime.execute(
    request,
    @MoonCache.Timestamp::from_seconds(20),
  )
  assert_true(response.source is StaleSource)
  assert_eq(response.body, b"stale")
  assert_eq(transport.call_count(), 0)
}

///|
test "runtime stale-if-error falls back after a transport failure" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry(
    [],
    [
      ("Cache-Control", "max-age=10, stale-if-error=30"),
      ("ETag", "\"v1\""),
      ("Warning", "110 example.test stale"),
    ],
    b"cached",
    0,
  )
  ignore(store.put(entry))
  let transport = @MoonCache.FakeTransport::with_outcomes([
    TransportFailure("connection refused"),
  ])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let response = try! runtime.execute(
    @MoonCache.RuntimeRequest::get("https://example.test/data"),
    @MoonCache.Timestamp::from_seconds(20),
  )
  assert_true(response.source is StaleSource)
  assert_eq(response.body, b"cached")
  assert_eq(response.meta.headers.get("age"), Some("20"))
  assert_false(response.meta.headers.contains("warning"))
  assert_true(response.trace.has_reason(StaleIfError))
  assert_true(response.trace.has_reason(StaleUpstreamError))
  assert_eq(store.variant_count(entry.request.uri), 1)
}

///|
test "runtime stale-if-error recognizes RFC 5861 error statuses" {
  for status in [500, 502, 503, 504] {
    let store = @MoonCache.MemoryStore::default()
    let entry = policy_entry(
      [],
      [("Cache-Control", "max-age=10, stale-if-error=30"), ("ETag", "\"v1\"")],
      b"cached",
      0,
    )
    ignore(store.put(entry))
    let transport = @MoonCache.FakeTransport::new([
      scripted_response(status, [], b"upstream error", 20, 20),
    ])
    let runtime = @MoonCache.CachedRuntime::new(
      store,
      transport,
      private_options(),
    )
    let response = try! runtime.execute(
      @MoonCache.RuntimeRequest::get("https://example.test/data"),
      @MoonCache.Timestamp::from_seconds(20),
    )
    assert_true(response.source is StaleSource)
    assert_eq(response.meta.status, 200)
    assert_eq(response.body, b"cached")
    assert_eq(store.variant_count(entry.request.uri), 1)
  }
}

///|
test "runtime stale-if-error also protects stale entries without validators" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry(
    [],
    [("Cache-Control", "max-age=10, stale-if-error=30")],
    b"cached",
    0,
  )
  ignore(store.put(entry))
  let transport = @MoonCache.FakeTransport::new([
    scripted_response(503, [], b"unavailable", 20, 20),
  ])
  let response = try! @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  ).execute(
    @MoonCache.RuntimeRequest::get("https://example.test/data"),
    @MoonCache.Timestamp::from_seconds(20),
  )
  assert_true(response.source is StaleSource)
  assert_eq(response.body, b"cached")
}

///|
test "request stale-if-error permits fallback without a response extension" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry(
    [],
    [("Cache-Control", "max-age=10"), ("ETag", "\"v1\"")],
    b"cached",
    0,
  )
  ignore(store.put(entry))
  let transport = @MoonCache.FakeTransport::with_outcomes([
    TransportFailure("DNS failure"),
  ])
  let request = @MoonCache.RuntimeRequest::new(
    policy_request("GET", [("Cache-Control", "stale-if-error=30")]),
    b"",
  )
  let response = try! @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  ).execute(request, @MoonCache.Timestamp::from_seconds(20))
  assert_true(response.source is StaleSource)
}

///|
test "stale-if-error outside its window propagates transport failure" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry(
    [],
    [("Cache-Control", "max-age=10, stale-if-error=5"), ("ETag", "\"v1\"")],
    b"cached",
    0,
  )
  ignore(store.put(entry))
  let transport = @MoonCache.FakeTransport::with_outcomes([
    TransportFailure("origin unavailable"),
  ])
  let result : Result[@MoonCache.RuntimeResponse, @MoonCache.RuntimeError] = Ok(
    @MoonCache.CachedRuntime::new(store, transport, private_options()).execute(
      @MoonCache.RuntimeRequest::get("https://example.test/data"),
      @MoonCache.Timestamp::from_seconds(20),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(RuntimeTransportFailure("origin unavailable")))
  assert_eq(store.variant_count(entry.request.uri), 1)
}

///|
test "must-revalidate blocks stale-if-error fallback" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry(
    [],
    [
      ("Cache-Control", "max-age=10, must-revalidate, stale-if-error=30"),
      ("ETag", "\"v1\""),
    ],
    b"cached",
    0,
  )
  ignore(store.put(entry))
  let transport = @MoonCache.FakeTransport::with_outcomes([
    TransportFailure("offline"),
  ])
  let result : Result[@MoonCache.RuntimeResponse, @MoonCache.RuntimeError] = Ok(
    @MoonCache.CachedRuntime::new(store, transport, private_options()).execute(
      @MoonCache.RuntimeRequest::get("https://example.test/data"),
      @MoonCache.Timestamp::from_seconds(20),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(RuntimeTransportFailure("offline")))
}

///|
test "server error beyond stale-if-error window does not evict old entry" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry(
    [],
    [("Cache-Control", "max-age=10, stale-if-error=5"), ("ETag", "\"v1\"")],
    b"cached",
    0,
  )
  ignore(store.put(entry))
  let transport = @MoonCache.FakeTransport::new([
    scripted_response(503, [], b"unavailable", 20, 20),
  ])
  let response = try! @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  ).execute(
    @MoonCache.RuntimeRequest::get("https://example.test/data"),
    @MoonCache.Timestamp::from_seconds(20),
  )
  assert_eq(response.meta.status, 503)
  assert_true(response.trace.has_reason(StaleWindowExceeded))
  assert_eq(store.variant_count(entry.request.uri), 1)
  assert_eq(store.peek_variants(entry.request.uri)[0].body, b"cached")
}

///|
test "HEAD stale-if-error fallback never returns the cached GET body" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry(
    [],
    [("Cache-Control", "max-age=10, stale-if-error=30"), ("ETag", "\"v1\"")],
    b"cached",
    0,
  )
  ignore(store.put(entry))
  let transport = @MoonCache.FakeTransport::with_outcomes([
    TransportFailure("offline"),
  ])
  let response = try! @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  ).execute(
    @MoonCache.RuntimeRequest::head("https://example.test/data"),
    @MoonCache.Timestamp::from_seconds(20),
  )
  assert_true(response.source is StaleSource)
  assert_eq(response.body, b"")
}

///|
test "runtime trace contains primary key and selected variant" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry(
    [("Accept-Language", "en")],
    [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
    b"english",
    0,
  )
  ignore(store.put(entry))
  let transport = @MoonCache.FakeTransport::new([])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  let response = try! runtime.execute(
    @MoonCache.RuntimeRequest::new(
      policy_request("GET", [("Accept-Language", "en")]),
      b"",
    ),
    @MoonCache.Timestamp::from_seconds(1),
  )
  assert_eq(response.trace.primary_key, Some("GET https://example.test/data"))
  assert_true(
    response.trace.selected_variant.unwrap().contains("accept-language=en"),
  )
}

///|
test "runtime exposes store stats through wrapper" {
  let store = @MoonCache.MemoryStore::default()
  let transport = @MoonCache.FakeTransport::new([])
  let runtime = @MoonCache.CachedRuntime::new(
    store,
    transport,
    private_options(),
  )
  assert_eq(runtime.store_stats().entries, 0)
}
