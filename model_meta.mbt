///|
pub fn normalize_method(value : String) -> String {
  value.trim().to_upper().to_owned()
}

///|
/// Metadata supplied to the cache policy. The request time is injected by the
/// caller and never read from a system clock.
pub(all) struct RequestMeta {
  http_method : String
  uri : String
  headers : HeaderMap
  request_time : Timestamp
} derive(Eq, Debug)

///|
pub fn RequestMeta::new(
  http_method : String,
  uri : String,
  headers : HeaderMap,
  request_time : Timestamp,
) -> RequestMeta {
  RequestMeta::{
    http_method: normalize_method(http_method),
    uri: uri.trim().to_owned(),
    headers,
    request_time,
  }
}

///|
pub fn RequestMeta::simple(http_method : String, uri : String) -> RequestMeta {
  RequestMeta::new(http_method, uri, HeaderMap::new(), Timestamp::zero())
}

///|
pub fn RequestMeta::with_headers(
  self : RequestMeta,
  headers : HeaderMap,
) -> RequestMeta {
  RequestMeta::{
    http_method: self.http_method,
    uri: self.uri,
    headers,
    request_time: self.request_time,
  }
}

///|
pub fn RequestMeta::with_request_time(
  self : RequestMeta,
  request_time : Timestamp,
) -> RequestMeta {
  RequestMeta::{
    http_method: self.http_method,
    uri: self.uri,
    headers: self.headers,
    request_time,
  }
}

///|
/// Normalized response metadata. `body_complete` lets adapters conservatively
/// reject interrupted or size-limited bodies.
pub(all) struct ResponseMeta {
  status : Int
  headers : HeaderMap
  request_time : Timestamp
  response_time : Timestamp
  body_complete : Bool
} derive(Eq, Debug)

///|
pub fn ResponseMeta::new(
  status : Int,
  headers : HeaderMap,
  request_time : Timestamp,
  response_time : Timestamp,
  body_complete : Bool,
) -> ResponseMeta {
  ResponseMeta::{ status, headers, request_time, response_time, body_complete }
}

///|
pub fn ResponseMeta::complete(
  status : Int,
  headers : HeaderMap,
  request_time : Timestamp,
  response_time : Timestamp,
) -> ResponseMeta {
  ResponseMeta::new(status, headers, request_time, response_time, true)
}

///|
pub(all) enum CacheMode {
  Private
  Shared
} derive(Eq, Compare, Debug)

///|
pub fn CacheMode::label(self : CacheMode) -> String {
  match self {
    Private => "private"
    Shared => "shared"
  }
}

///|
pub fn CacheMode::from_string(value : String) -> CacheMode? {
  match value.trim().to_lower().to_owned() {
    "private" => Some(Private)
    "shared" => Some(Shared)
    _ => None
  }
}

///|
/// Policy settings with privacy-preserving defaults.
pub(all) struct CacheOptions {
  mode : CacheMode
  allow_heuristic_freshness : Bool
  heuristic_fraction_per_mille : Int
  max_heuristic_lifetime : DeltaSeconds
  allow_shared_authorized : Bool
  cache_head_responses : Bool
  strip_sensitive_metadata : Bool
} derive(Eq, Debug)

///|
pub fn CacheOptions::private_cache() -> CacheOptions {
  CacheOptions::{
    mode: Private,
    allow_heuristic_freshness: true,
    heuristic_fraction_per_mille: 100,
    max_heuristic_lifetime: DeltaSeconds::from_seconds(86_400),
    allow_shared_authorized: false,
    cache_head_responses: true,
    strip_sensitive_metadata: true,
  }
}

///|
pub fn CacheOptions::shared_cache() -> CacheOptions {
  CacheOptions::{
    mode: Shared,
    allow_heuristic_freshness: true,
    heuristic_fraction_per_mille: 100,
    max_heuristic_lifetime: DeltaSeconds::from_seconds(86_400),
    allow_shared_authorized: false,
    cache_head_responses: true,
    strip_sensitive_metadata: true,
  }
}

///|
pub fn CacheOptions::with_heuristic_freshness(
  self : CacheOptions,
  enabled : Bool,
) -> CacheOptions {
  CacheOptions::{ ..self, allow_heuristic_freshness: enabled }
}

///|
pub fn CacheOptions::with_shared_authorized(
  self : CacheOptions,
  enabled : Bool,
) -> CacheOptions {
  CacheOptions::{ ..self, allow_shared_authorized: enabled }
}

///|
pub fn CacheOptions::with_cache_head_responses(
  self : CacheOptions,
  enabled : Bool,
) -> CacheOptions {
  CacheOptions::{ ..self, cache_head_responses: enabled }
}

///|
pub fn CacheOptions::with_heuristic_settings(
  self : CacheOptions,
  fraction_per_mille : Int,
  maximum : DeltaSeconds,
) -> CacheOptions {
  CacheOptions::{
    ..self,
    heuristic_fraction_per_mille: fraction_per_mille,
    max_heuristic_lifetime: maximum,
  }
}

///|
pub(all) struct StoredPolicy {
  cacheable : Bool
  freshness_lifetime : DeltaSeconds
  requires_revalidation : Bool
  no_store : Bool
  vary_star : Bool
  must_revalidate : Bool
  proxy_revalidate : Bool
  is_private : Bool
  is_public : Bool
} derive(Eq, Debug)

///|
pub fn StoredPolicy::uncacheable() -> StoredPolicy {
  StoredPolicy::{
    cacheable: false,
    freshness_lifetime: DeltaSeconds::zero(),
    requires_revalidation: false,
    no_store: true,
    vary_star: false,
    must_revalidate: false,
    proxy_revalidate: false,
    is_private: false,
    is_public: false,
  }
}

///|
pub fn StoredPolicy::cacheable(
  lifetime : DeltaSeconds,
  requires_revalidation : Bool,
) -> StoredPolicy {
  StoredPolicy::{
    cacheable: true,
    freshness_lifetime: lifetime,
    requires_revalidation,
    no_store: false,
    vary_star: false,
    must_revalidate: false,
    proxy_revalidate: false,
    is_private: false,
    is_public: false,
  }
}

///|
pub fn StoredPolicy::from_directives(
  lifetime : DeltaSeconds,
  directives : CacheControl,
  vary_star : Bool,
) -> StoredPolicy {
  StoredPolicy::{
    cacheable: !directives.no_store && !vary_star,
    freshness_lifetime: lifetime,
    requires_revalidation: directives.no_cache,
    no_store: directives.no_store,
    vary_star,
    must_revalidate: directives.must_revalidate,
    proxy_revalidate: directives.proxy_revalidate,
    is_private: directives.is_private,
    is_public: directives.is_public,
  }
}
