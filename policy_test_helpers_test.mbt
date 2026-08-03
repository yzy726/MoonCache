///|
fn policy_headers(pairs : Array[(String, String)]) -> @MoonCache.HeaderMap {
  @MoonCache.HeaderMap::from_pairs(pairs)
}

///|
fn policy_request(
  http_method : String,
  pairs : Array[(String, String)],
) -> @MoonCache.RequestMeta {
  @MoonCache.RequestMeta::new(
    http_method,
    "https://example.test/data",
    policy_headers(pairs),
    @MoonCache.Timestamp::from_seconds(0),
  )
}

///|
fn policy_response(
  status : Int,
  pairs : Array[(String, String)],
  request_time : Int64,
  response_time : Int64,
  complete : Bool,
) -> @MoonCache.ResponseMeta {
  @MoonCache.ResponseMeta::new(
    status,
    policy_headers(pairs),
    @MoonCache.Timestamp::from_seconds(request_time),
    @MoonCache.Timestamp::from_seconds(response_time),
    complete,
  )
}

///|
fn private_options() -> @MoonCache.CacheOptions {
  @MoonCache.CacheOptions::private_cache()
}

///|
fn shared_options() -> @MoonCache.CacheOptions {
  @MoonCache.CacheOptions::shared_cache()
}

///|
fn reason_codes(reasons : Array[@MoonCache.CacheReason]) -> Array[String] {
  reasons.map(fn(reason) { reason.code.code() })
}
