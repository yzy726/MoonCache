///|
test "HTTP date parses Unix epoch" {
  let parsed = @MoonCache.parse_http_date("Thu, 01 Jan 1970 00:00:00 GMT")
  assert_eq(parsed.unwrap().seconds(), 0)
}

///|
test "HTTP date parses RFC example" {
  let parsed = @MoonCache.parse_http_date("Sun, 06 Nov 1994 08:49:37 GMT")
  assert_eq(parsed.unwrap().seconds(), 784_111_777)
}

///|
test "HTTP date parses leap-year day" {
  let parsed = @MoonCache.parse_http_date("Tue, 29 Feb 2000 00:00:00 GMT")
  assert_eq(parsed.unwrap().seconds(), 951_782_400)
}

///|
test "HTTP date rejects non-leap February 29" {
  assert_eq(@MoonCache.parse_http_date("Mon, 29 Feb 1999 00:00:00 GMT"), None)
}

///|
test "HTTP date rejects invalid month" {
  assert_eq(@MoonCache.parse_http_date("Thu, 01 Xxx 1970 00:00:00 GMT"), None)
}

///|
test "HTTP date rejects invalid day" {
  assert_eq(@MoonCache.parse_http_date("Thu, 32 Jan 1970 00:00:00 GMT"), None)
}

///|
test "HTTP date rejects invalid hour" {
  assert_eq(@MoonCache.parse_http_date("Thu, 01 Jan 1970 24:00:00 GMT"), None)
}

///|
test "HTTP date rejects non-GMT zone" {
  assert_eq(@MoonCache.parse_http_date("Thu, 01 Jan 1970 00:00:00 UTC"), None)
}

///|
test "HTTP date rejects malformed weekday" {
  assert_eq(@MoonCache.parse_http_date("Bad, 01 Jan 1970 00:00:00 GMT"), None)
}

///|
test "HTTP date trims optional boundary whitespace" {
  let parsed = @MoonCache.parse_http_date(" \tThu, 01 Jan 1970 00:00:01 GMT\t ")
  assert_eq(parsed.unwrap().seconds(), 1)
}
