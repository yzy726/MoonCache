///|
test "header names are case insensitive" {
  let headers = @MoonCache.HeaderMap::new()
  assert_true(headers.set("Content-Type", " text/plain "))
  assert_eq(headers.get("content-type"), Some("text/plain"))
  assert_eq(headers.get("CONTENT-TYPE"), Some("text/plain"))
}

///|
test "header append retains repeated values" {
  let headers = @MoonCache.HeaderMap::new()
  assert_true(headers.append("Cache-Control", "max-age=60"))
  assert_true(headers.append("cache-control", "public"))
  assert_eq(headers.get_all("CACHE-CONTROL"), ["max-age=60", "public"])
  assert_eq(headers.get("cache-control"), Some("max-age=60, public"))
}

///|
test "header set replaces repeated values" {
  let headers = @MoonCache.HeaderMap::from_pairs([
    ("x-test", "one"),
    ("X-Test", "two"),
  ])
  assert_true(headers.set("x-test", "three"))
  assert_eq(headers.get_all("x-test"), ["three"])
}

///|
test "missing and empty headers are distinct" {
  let headers = @MoonCache.HeaderMap::new()
  assert_true(headers.set("x-empty", ""))
  assert_true(headers.contains("X-Empty"))
  assert_eq(headers.get("x-empty"), Some(""))
  assert_false(headers.contains("x-missing"))
  assert_eq(headers.get("x-missing"), None)
}

///|
test "invalid header names are rejected" {
  let headers = @MoonCache.HeaderMap::new()
  assert_false(headers.set("", "value"))
  assert_false(headers.set("bad name", "value"))
  assert_false(headers.append("bad:name", "value"))
  assert_true(headers.is_empty())
}

///|
test "valid token punctuation is accepted" {
  assert_true(@MoonCache.is_valid_header_name("x!#$%&'*+-.^_`|~"))
}

///|
test "header names and pairs are deterministic" {
  let headers = @MoonCache.HeaderMap::from_pairs([
    ("z-last", "z"),
    ("A-First", "a"),
    ("z-last", "z2"),
  ])
  assert_eq(headers.names(), ["a-first", "z-last"])
  assert_eq(headers.pairs(), [
    ("a-first", "a"),
    ("z-last", "z"),
    ("z-last", "z2"),
  ])
}

///|
test "header copy is deep" {
  let original = @MoonCache.HeaderMap::from_pairs([("x", "one")])
  let copied = original.copy()
  assert_true(copied.append("x", "two"))
  assert_eq(original.get_all("x"), ["one"])
  assert_eq(copied.get_all("x"), ["one", "two"])
}

///|
test "header remove reports presence" {
  let headers = @MoonCache.HeaderMap::from_pairs([("x", "one")])
  assert_true(headers.remove("X"))
  assert_false(headers.remove("x"))
  assert_true(headers.is_empty())
}

///|
test "header overlay replaces named fields" {
  let base = @MoonCache.HeaderMap::from_pairs([
    ("cache-control", "max-age=60"),
    ("etag", "\"old\""),
  ])
  let updates = @MoonCache.HeaderMap::from_pairs([
    ("etag", "\"new\""),
    ("date", "Sun, 06 Nov 1994 08:49:37 GMT"),
  ])
  let merged = base.overlay(updates)
  assert_eq(merged.get("cache-control"), Some("max-age=60"))
  assert_eq(merged.get("etag"), Some("\"new\""))
  assert_true(merged.contains("date"))
}

///|
test "diagnostic headers redact credentials and cookies" {
  let headers = @MoonCache.HeaderMap::from_pairs([
    ("Authorization", "Bearer secret"),
    ("Cookie", "session=secret"),
    ("Set-Cookie", "session=secret"),
    ("Accept", "application/json"),
  ])
  let safe = headers.redacted()
  assert_eq(safe.get("authorization"), Some("<redacted>"))
  assert_eq(safe.get("cookie"), Some("<redacted>"))
  assert_eq(safe.get("set-cookie"), Some("<redacted>"))
  assert_eq(safe.get("accept"), Some("application/json"))
}
