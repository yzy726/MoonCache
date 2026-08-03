///|
test "http11 absolute request converts to runtime metadata" {
  let source = @wire11.Request::new("GET", "https://example.test/data")
    .header("Accept-Language", "en")
    .body([b'a'])
  let request = try! request_to_runtime(
    source,
    @mooncache.Timestamp::from_seconds(7),
  )
  assert_eq(request.meta.http_method, "GET")
  assert_eq(request.meta.uri, "https://example.test/data")
  assert_eq(request.meta.headers.get("accept-language"), Some("en"))
  assert_eq(request.meta.request_time.seconds(), 7L)
  assert_eq(request.body, b"a")
}

///|
test "http11 origin form accepts caller supplied absolute URI" {
  let source = @wire11.Request::new("GET", "/data")
  let request = try! request_to_runtime_at_uri(
    source,
    "https://example.test/data",
    @mooncache.Timestamp::zero(),
  )
  assert_eq(request.meta.uri, "https://example.test/data")
}

///|
test "http11 origin form without authority is rejected" {
  let source = @wire11.Request::new("GET", "/data")
  let result : Result[@mooncache.RuntimeRequest, Http11AdapterError] = Ok(
    request_to_runtime(source, @mooncache.Timestamp::zero()),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(AbsoluteUriRequired("/data")))
}

///|
test "http11 duplicate response headers survive conversion" {
  let source = @wire11.Response::new(200, "OK")
    .header("Cache-Control", "max-age=60")
    .header("Warning", "199 first")
    .header("Warning", "299 second")
    .body([b'o', b'k'])
  let response = try! response_to_transport(
    source,
    @mooncache.Timestamp::zero(),
    @mooncache.Timestamp::from_seconds(1),
  )
  assert_eq(response.meta.status, 200)
  assert_eq(response.meta.headers.get_all("warning"), [
    "199 first", "299 second",
  ])
  assert_eq(response.body, b"ok")
  assert_true(response.meta.body_complete)
}

///|
test "http11 incomplete response remains incomplete" {
  let response = try! response_to_transport(
    @wire11.Response::new(200, "OK"),
    @mooncache.Timestamp::zero(),
    @mooncache.Timestamp::zero(),
    body_complete=false,
  )
  assert_false(response.meta.body_complete)
}

///|
test "runtime request converts back to HTTP11" {
  let headers = @mooncache.HeaderMap::from_pairs([("X-Test", "yes")])
  let request = @mooncache.RuntimeRequest::new(
    @mooncache.RequestMeta::new(
      "POST",
      "https://example.test/items",
      headers,
      @mooncache.Timestamp::zero(),
    ),
    b"payload",
  )
  let converted = runtime_request_to_http11(request)
  assert_eq(converted.http_method, "POST")
  assert_eq(converted.uri, "https://example.test/items")
  assert_eq(converted.get_header("x-test"), Some("yes"))
  assert_eq(converted.body, [b'p', b'a', b'y', b'l', b'o', b'a', b'd'])
}

///|
test "runtime response converts back with standard reason phrase" {
  let response = @mooncache.RuntimeResponse::{
    meta: @mooncache.ResponseMeta::complete(
      504,
      @mooncache.HeaderMap::new(),
      @mooncache.Timestamp::zero(),
      @mooncache.Timestamp::zero(),
    ),
    body: b"",
    source: OnlyIfCachedSource,
    trace: @mooncache.CacheTrace::new(OnlyIfCachedMiss),
  }
  let converted = runtime_response_to_http11(response)
  assert_eq(converted.status_code, 504)
  assert_eq(converted.reason_phrase, "Gateway Timeout")
}

///|
test "invalid HTTP11 header name is rejected" {
  let source = @wire11.Request::{
    http_method: "GET",
    uri: "https://example.test/",
    version: "HTTP/1.1",
    headers: [("bad header", "value")],
    body: [],
  }
  let result : Result[@mooncache.RuntimeRequest, Http11AdapterError] = Ok(
    request_to_runtime(source, @mooncache.Timestamp::zero()),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(InvalidHeaderName("bad header")))
}
