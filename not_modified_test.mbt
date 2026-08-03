///|
fn merge_entry(
  cached_headers : Array[(String, String)],
  validation_headers : Array[(String, String)],
) -> @MoonCache.NotModifiedResult {
  let entry = policy_entry([], cached_headers, b"cached body", 1)
  try! @MoonCache.merge_not_modified(
    entry,
    policy_response(304, validation_headers, 10, 11, true),
    private_options(),
    @MoonCache.Timestamp::from_seconds(11),
  )
}

///|
test "304 merge preserves cached status and body" {
  let result = merge_entry([("Cache-Control", "max-age=60")], [
    ("Date", "Thu, 01 Jan 1970 00:00:11 GMT"),
  ])
  assert_eq(result.entry.response.status, 200)
  assert_eq(result.entry.body, b"cached body")
}

///|
test "304 merge replaces Date Age and ETag metadata" {
  let result = merge_entry(
    [
      ("Cache-Control", "max-age=60"),
      ("Date", "Thu, 01 Jan 1970 00:00:00 GMT"),
      ("Age", "1"),
      ("ETag", "\"old\""),
    ],
    [
      ("Date", "Thu, 01 Jan 1970 00:00:11 GMT"),
      ("Age", "2"),
      ("ETag", "\"new\""),
    ],
  )
  assert_eq(
    result.entry.response.headers.get("date"),
    Some("Thu, 01 Jan 1970 00:00:11 GMT"),
  )
  assert_eq(result.entry.response.headers.get("age"), Some("2"))
  assert_eq(result.entry.response.headers.get("etag"), Some("\"new\""))
}

///|
test "304 merge preserves metadata not mentioned" {
  let result = merge_entry(
    [("Cache-Control", "max-age=60"), ("Content-Type", "application/json")],
    [("ETag", "\"new\"")],
  )
  assert_eq(
    result.entry.response.headers.get("content-type"),
    Some("application/json"),
  )
}

///|
test "304 merge recomputes freshness policy" {
  let result = merge_entry([("Cache-Control", "max-age=10")], [
    ("Cache-Control", "max-age=120"),
  ])
  assert_eq(result.entry.policy.freshness_lifetime.seconds(), 120)
  assert_true(result.storage.storable)
}

///|
test "304 merge does not replace cached Content-Length" {
  let result = merge_entry(
    [("Cache-Control", "max-age=60"), ("Content-Length", "11")],
    [("Content-Length", "0")],
  )
  assert_eq(result.entry.response.headers.get("content-length"), Some("11"))
}

///|
test "304 merge excludes standard hop-by-hop fields" {
  let result = merge_entry([("Cache-Control", "max-age=60")], [
    ("Transfer-Encoding", "chunked"),
    ("Keep-Alive", "timeout=5"),
  ])
  assert_false(result.entry.response.headers.contains("transfer-encoding"))
  assert_false(result.entry.response.headers.contains("keep-alive"))
}

///|
test "304 merge excludes Connection-named fields" {
  let result = merge_entry([("Cache-Control", "max-age=60")], [
    ("Connection", "X-Hop"),
    ("X-Hop", "secret"),
  ])
  assert_false(result.entry.response.headers.contains("connection"))
  assert_false(result.entry.response.headers.contains("x-hop"))
}

///|
test "304 merge removes stale Warning metadata" {
  let result = merge_entry(
    [("Cache-Control", "max-age=60"), ("Warning", "110 example.test stale")],
    [],
  )
  assert_false(result.entry.response.headers.contains("warning"))
}

///|
test "304 merge updates request response and storage times" {
  let result = merge_entry([("Cache-Control", "max-age=60")], [])
  assert_eq(result.entry.response.request_time.seconds(), 10)
  assert_eq(result.entry.response.response_time.seconds(), 11)
  assert_eq(result.entry.stored_at.seconds(), 11)
  assert_eq(result.entry.last_accessed_at.seconds(), 11)
}

///|
test "304 merge recomputes changed Vary key" {
  let request = policy_request("GET", [
    ("Accept", "text/plain"),
    ("Accept-Language", "en"),
  ])
  let response = policy_response(
    200,
    [("Cache-Control", "max-age=60"), ("Vary", "Accept")],
    0,
    0,
    true,
  )
  let old_variant = @MoonCache.build_variant_key(
    request.headers,
    @MoonCache.parse_vary(response.headers),
  ).unwrap()
  let entry = @MoonCache.StoredEntry::new(
    @MoonCache.primary_cache_key(request).unwrap(),
    old_variant,
    request,
    response,
    b"body",
    @MoonCache.StoredPolicy::cacheable(
      @MoonCache.DeltaSeconds::from_seconds(60),
      false,
    ),
    @MoonCache.Timestamp::zero(),
  )
  let result = try! @MoonCache.merge_not_modified(
    entry,
    policy_response(304, [("Vary", "Accept-Language")], 1, 2, true),
    private_options(),
    @MoonCache.Timestamp::from_seconds(2),
  )
  assert_false(result.entry.variant_key == old_variant)
  assert_true(result.entry.variant_key.label.contains("accept-language=en"))
}

///|
test "304 no-store makes merged entry non-storable" {
  let result = merge_entry([("Cache-Control", "max-age=60")], [
    ("Cache-Control", "no-store"),
  ])
  assert_false(result.storage.storable)
  assert_false(result.entry.policy.cacheable)
}

///|
test "304 merge records stable reason" {
  let result = merge_entry([("Cache-Control", "max-age=60")], [])
  assert_true(reason_codes(result.reasons).contains("MC_REVAL_005"))
}

///|
test "304 merge rejects non-304 status" {
  let entry = policy_entry([], [("Cache-Control", "max-age=60")], b"body", 1)
  let result : Result[@MoonCache.NotModifiedResult, @MoonCache.ValidationError] = Ok(
    @MoonCache.merge_not_modified(
      entry,
      policy_response(200, [], 1, 2, true),
      private_options(),
      @MoonCache.Timestamp::from_seconds(2),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(ExpectedNotModified(200)))
}
