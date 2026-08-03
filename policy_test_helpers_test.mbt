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

///|
fn policy_entry(
  request_pairs : Array[(String, String)],
  response_pairs : Array[(String, String)],
  body : Bytes,
  stored_at : Int64,
) -> @MoonCache.StoredEntry {
  let request = policy_request("GET", request_pairs)
  let response = policy_response(200, response_pairs, 0, 0, true)
  let key = @MoonCache.primary_cache_key(request).unwrap()
  let variant = @MoonCache.build_variant_key(
    request.headers,
    @MoonCache.parse_vary(response.headers),
  ).unwrap_or(@MoonCache.VariantKey::empty())
  let storage = @MoonCache.evaluate_storage(
    request,
    response,
    private_options(),
  )
  @MoonCache.StoredEntry::new(
    key,
    variant,
    request,
    response,
    body,
    storage.policy,
    @MoonCache.Timestamp::from_seconds(stored_at),
  )
}

///|
fn policy_entry_for_uri(
  uri : String,
  request_pairs : Array[(String, String)],
  response_pairs : Array[(String, String)],
  body : Bytes,
  stored_at : Int64,
) -> @MoonCache.StoredEntry {
  let request = @MoonCache.RequestMeta::new(
    "GET",
    uri,
    policy_headers(request_pairs),
    @MoonCache.Timestamp::zero(),
  )
  let response = policy_response(200, response_pairs, 0, 0, true)
  let key = @MoonCache.primary_cache_key(request).unwrap()
  let variant = @MoonCache.build_variant_key(
    request.headers,
    @MoonCache.parse_vary(response.headers),
  ).unwrap_or(@MoonCache.VariantKey::empty())
  let storage = @MoonCache.evaluate_storage(
    request,
    response,
    private_options(),
  )
  @MoonCache.StoredEntry::new(
    key,
    variant,
    request,
    response,
    body,
    storage.policy,
    @MoonCache.Timestamp::from_seconds(stored_at),
  )
}

///|
fn scripted_response(
  status : Int,
  pairs : Array[(String, String)],
  body : Bytes,
  request_time : Int64,
  response_time : Int64,
) -> @MoonCache.TransportResponse {
  @MoonCache.TransportResponse::new(
    policy_response(status, pairs, request_time, response_time, true),
    body,
  )
}
