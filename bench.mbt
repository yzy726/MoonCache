///|
fn bench_entry(uri : String, language : String, tick : Int64) -> StoredEntry {
  let request_headers = HeaderMap::new()
  ignore(request_headers.append("Accept-Language", language))
  let response_headers = HeaderMap::new()
  ignore(response_headers.append("Cache-Control", "max-age=60"))
  let request = RequestMeta::new(
    "GET",
    uri,
    request_headers,
    Timestamp::from_seconds(tick),
  )
  let response = ResponseMeta::complete(
    200,
    response_headers,
    Timestamp::from_seconds(tick),
    Timestamp::from_seconds(tick),
  )
  let primary = PrimaryCacheKey::from_request(request).unwrap()
  let variant = build_variant_key(request.headers, parse_vary(response.headers)).unwrap()
  StoredEntry::new(
    primary,
    variant,
    request,
    response,
    b"benchmark payload",
    StoredPolicy::cacheable(DeltaSeconds::from_seconds(60), false),
    Timestamp::from_seconds(tick),
  )
}

///|
test (bench : @bench.T) {
  let headers = HeaderMap::new()
  ignore(headers.append("Cache-Control", "max-age=3600"))
  ignore(headers.append("Date", "Thu, 01 Jan 1970 00:01:00 GMT"))
  let response = ResponseMeta::complete(
    200,
    headers,
    Timestamp::from_seconds(0),
    Timestamp::from_seconds(2),
  )
  let request = RequestMeta::simple("GET", "https://example.test/age")
  let options = CacheOptions::private_cache()
  for _ in 0..<1000 {
    bench.keep(
      evaluate_cached_response(
        request,
        response,
        options,
        Timestamp::from_seconds(120),
      ),
    )
  }
}

///|
test (bench : @bench.T) {
  let stored = HeaderMap::new()
  ignore(stored.append("Vary", "Accept-Language, User-Agent"))
  let vary = parse_vary(stored)
  let mut acc = 0
  for i in 0..<2000 {
    let headers = HeaderMap::new()
    ignore(headers.append("Accept-Language", "en-\{i % 8}"))
    ignore(headers.append("User-Agent", "agent/\{i % 4}"))
    match build_variant_key(headers, vary) {
      Some(key) => acc += key.label.length()
      None => ()
    }
  }
  bench.keep(acc)
}

///|
test (bench : @bench.T) {
  let store = MemoryStore::default()
  let entries : Array[StoredEntry] = []
  for i in 0..<64 {
    entries.push(
      bench_entry("https://example.test/bench/\{i}", "en", i.to_int64()),
    )
  }
  for entry in entries {
    ignore(store.put(entry))
  }
  for i in 0..<4000 {
    let key = PrimaryCacheKey::from_request(
      RequestMeta::simple("GET", "https://example.test/bench/\{i % 64}"),
    ).unwrap()
    bench.keep(store.find_variants(key).length())
  }
}

///|
priv struct BenchOrigin {
  mut calls : Int
}

///|
impl Transport for BenchOrigin with fn execute(self, _request) -> TransportResponse raise TransportError {
  self.calls += 1
  TransportResponse::{
    meta: ResponseMeta::complete(
      200,
      single_header("Cache-Control", "max-age=60"),
      Timestamp::zero(),
      Timestamp::zero(),
    ),
    body: b"bench body",
  }
}

///|
test (bench : @bench.T) {
  let origin = BenchOrigin::{ calls: 0 }
  let runtime = CachedRuntime::new(
    MemoryStore::default(),
    origin,
    CacheOptions::private_cache(),
  )
  let request = RuntimeRequest::get("https://example.test/runtime")
  for i in 0..<500 {
    bench.keep(
      runtime.execute(request.copy(), Timestamp::from_seconds(i.to_int64())),
    )
  }
  bench.keep(origin.calls)
}

///|
fn single_header(name : String, value : String) -> HeaderMap {
  let headers = HeaderMap::new()
  ignore(headers.append(name, value))
  headers
}
