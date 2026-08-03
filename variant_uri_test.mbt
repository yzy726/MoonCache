///|
test "URI normalization lowercases scheme and host" {
  assert_eq(
    @MoonCache.normalize_cache_uri("HTTP://EXAMPLE.TEST/Data"),
    Some("http://example.test/Data"),
  )
}

///|
test "URI normalization removes default HTTP port" {
  assert_eq(
    @MoonCache.normalize_cache_uri("http://example.test:80/data"),
    Some("http://example.test/data"),
  )
}

///|
test "URI normalization removes default HTTPS port" {
  assert_eq(
    @MoonCache.normalize_cache_uri("https://example.test:443/data"),
    Some("https://example.test/data"),
  )
}

///|
test "URI normalization retains non-default port" {
  assert_eq(
    @MoonCache.normalize_cache_uri("https://example.test:8443/data"),
    Some("https://example.test:8443/data"),
  )
}

///|
test "URI normalization supplies empty path slash" {
  assert_eq(
    @MoonCache.normalize_cache_uri("https://example.test"),
    Some("https://example.test/"),
  )
}

///|
test "URI normalization preserves query text" {
  assert_eq(
    @MoonCache.normalize_cache_uri("https://example.test?a=1&B=Two"),
    Some("https://example.test/?a=1&B=Two"),
  )
}

///|
test "URI normalization removes fragment" {
  assert_eq(
    @MoonCache.normalize_cache_uri("https://example.test/data#section"),
    Some("https://example.test/data"),
  )
}

///|
test "URI normalization resolves current dot segment" {
  assert_eq(
    @MoonCache.normalize_cache_uri("https://example.test/a/./b"),
    Some("https://example.test/a/b"),
  )
}

///|
test "URI normalization resolves parent dot segment" {
  assert_eq(
    @MoonCache.normalize_cache_uri("https://example.test/a/b/../c"),
    Some("https://example.test/a/c"),
  )
}

///|
test "URI normalization preserves duplicate path slash" {
  assert_eq(
    @MoonCache.normalize_cache_uri("https://example.test/a//b"),
    Some("https://example.test/a//b"),
  )
}

///|
test "URI normalization rejects unsupported schemes" {
  assert_eq(@MoonCache.normalize_cache_uri("ftp://example.test/a"), None)
}

///|
test "URI normalization rejects relative URI" {
  assert_eq(@MoonCache.normalize_cache_uri("/relative"), None)
}

///|
test "URI normalization rejects userinfo authority" {
  assert_eq(
    @MoonCache.normalize_cache_uri("https://user@example.test/data"),
    None,
  )
}

///|
test "URI normalization handles bracketed IPv6 default port" {
  assert_eq(
    @MoonCache.normalize_cache_uri("HTTP://[2001:DB8::1]:80/data"),
    Some("http://[2001:db8::1]/data"),
  )
}

///|
test "GET and HEAD share primary cache key" {
  let get = policy_request("GET", [])
  let head = policy_request("HEAD", [])
  assert_eq(
    @MoonCache.primary_cache_key(get),
    @MoonCache.primary_cache_key(head),
  )
}

///|
test "primary key normalizes request URI" {
  let request = @MoonCache.RequestMeta::simple(
    "GET", "HTTPS://EXAMPLE.TEST:443/a/../data#x",
  )
  let key = @MoonCache.primary_cache_key(request).unwrap()
  assert_eq(key.label(), "GET https://example.test/data")
}

///|
test "origin comparison accounts for default ports" {
  assert_true(
    @MoonCache.same_cache_origin(
      "http://example.test:80/a", "HTTP://EXAMPLE.TEST/b",
    ),
  )
}

///|
test "origin comparison rejects different schemes" {
  assert_false(
    @MoonCache.same_cache_origin(
      "http://example.test/a", "https://example.test/a",
    ),
  )
}
