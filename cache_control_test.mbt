///|
test "cache-control recognizes no-cache and no-store" {
  let parsed = @MoonCache.parse_cache_control("no-cache, no-store")
  assert_true(parsed.no_cache)
  assert_true(parsed.no_store)
}

///|
test "cache-control directive names are case insensitive" {
  let parsed = @MoonCache.parse_cache_control("PUBLIC, Must-Revalidate")
  assert_true(parsed.is_public)
  assert_true(parsed.must_revalidate)
}

///|
test "cache-control distinguishes private and public flags" {
  let parsed = @MoonCache.parse_cache_control("private, public")
  assert_true(parsed.is_private)
  assert_true(parsed.is_public)
}

///|
test "cache-control parses max-age" {
  let parsed = @MoonCache.parse_cache_control("max-age=60")
  assert_eq(parsed.max_age.unwrap().seconds(), 60)
}

///|
test "cache-control parses quoted delta-seconds" {
  let parsed = @MoonCache.parse_cache_control("max-age=\"120\"")
  assert_eq(parsed.max_age.unwrap().seconds(), 120)
}

///|
test "cache-control repeated max-age uses conservative minimum" {
  let parsed = @MoonCache.parse_cache_control("max-age=120, max-age=30")
  assert_eq(parsed.max_age.unwrap().seconds(), 30)
}

///|
test "cache-control parses shared max age separately" {
  let parsed = @MoonCache.parse_cache_control("max-age=30, s-maxage=90")
  assert_eq(parsed.max_age.unwrap().seconds(), 30)
  assert_eq(parsed.shared_max_age.unwrap().seconds(), 90)
}

///|
test "cache-control parses request freshness constraints" {
  let parsed = @MoonCache.parse_cache_control(
    "max-age=20, min-fresh=5, only-if-cached",
  )
  assert_eq(parsed.max_age.unwrap().seconds(), 20)
  assert_eq(parsed.min_fresh.unwrap().seconds(), 5)
  assert_true(parsed.only_if_cached)
}

///|
test "cache-control max-stale without value is unbounded" {
  let parsed = @MoonCache.parse_cache_control("max-stale")
  assert_true(parsed.max_stale_unbounded)
  assert_eq(parsed.max_stale, None)
}

///|
test "cache-control bounded max-stale parses seconds" {
  let parsed = @MoonCache.parse_cache_control("max-stale=45")
  assert_false(parsed.max_stale_unbounded)
  assert_eq(parsed.max_stale.unwrap().seconds(), 45)
}

///|
test "cache-control parses stale extension windows" {
  let parsed = @MoonCache.parse_cache_control(
    "stale-if-error=300, stale-while-revalidate=30",
  )
  assert_eq(parsed.stale_if_error.unwrap().seconds(), 300)
  assert_eq(parsed.stale_while_revalidate.unwrap().seconds(), 30)
}

///|
test "cache-control recognizes proxy-revalidate and immutable" {
  let parsed = @MoonCache.parse_cache_control("proxy-revalidate, immutable")
  assert_true(parsed.proxy_revalidate)
  assert_true(parsed.immutable)
}

///|
test "cache-control ignores unknown extensions" {
  let parsed = @MoonCache.parse_cache_control("x-vendor=abc, max-age=10")
  assert_eq(parsed.max_age.unwrap().seconds(), 10)
  assert_false(parsed.malformed_delta)
}

///|
test "cache-control rejects negative delta-seconds" {
  let parsed = @MoonCache.parse_cache_control("max-age=-1")
  assert_eq(parsed.max_age, None)
  assert_true(parsed.malformed_delta)
}

///|
test "cache-control rejects signed positive delta-seconds" {
  assert_eq(@MoonCache.parse_delta_seconds("+1"), None)
}

///|
test "cache-control rejects fractional delta-seconds" {
  assert_eq(@MoonCache.parse_delta_seconds("1.5"), None)
}

///|
test "cache-control rejects overflowing delta-seconds" {
  assert_eq(@MoonCache.parse_delta_seconds("9223372036854775808"), None)
}

///|
test "cache-control accepts Int64 maximum delta-seconds" {
  let parsed = @MoonCache.parse_delta_seconds("9223372036854775807")
  assert_eq(parsed.unwrap().seconds(), @MoonCache.MAX_DELTA_SECONDS)
}

///|
test "cache-control missing numeric value is malformed" {
  let parsed = @MoonCache.parse_cache_control("max-age")
  assert_eq(parsed.max_age, None)
  assert_true(parsed.malformed_delta)
}

///|
test "legacy pragma no-cache applies only without cache-control" {
  let legacy = policy_headers([("Pragma", "no-cache")])
  let modern = policy_headers([
    ("Pragma", "no-cache"),
    ("Cache-Control", "max-age=10"),
  ])
  assert_true(@MoonCache.request_has_legacy_no_cache(legacy))
  assert_false(@MoonCache.request_has_legacy_no_cache(modern))
}
