///|
pub(all) enum FreshnessSource {
  SharedMaxAge
  MaxAge
  Expires
  HeuristicLastModified
  NoFreshness
} derive(Eq, Compare, Debug)

///|
pub fn FreshnessSource::label(self : FreshnessSource) -> String {
  match self {
    SharedMaxAge => "s-maxage"
    MaxAge => "max-age"
    Expires => "expires"
    HeuristicLastModified => "heuristic-last-modified"
    NoFreshness => "none"
  }
}

///|
pub fn FreshnessSource::reason(self : FreshnessSource) -> CacheReasonCode {
  match self {
    SharedMaxAge => FreshSharedMaxAge
    MaxAge => FreshMaxAge
    Expires => FreshExpires
    HeuristicLastModified => FreshHeuristic
    NoFreshness => FreshNone
  }
}

///|
pub(all) struct FreshnessCalculation {
  lifetime : DeltaSeconds
  source : FreshnessSource
  date_value : Timestamp
  expires_value : Timestamp?
  last_modified_value : Timestamp?
} derive(Eq, Debug)

///|
fn response_date_or_time(response : ResponseMeta) -> Timestamp {
  match response.headers.get_first("date") {
    Some(value) => parse_http_date(value).unwrap_or(response.response_time)
    None => response.response_time
  }
}

///|
fn parsed_header_date(headers : HeaderMap, name : String) -> Timestamp? {
  match headers.get_first(name) {
    Some(value) => parse_http_date(value)
    None => None
  }
}

///|
/// Calculate freshness lifetime using RFC directive precedence. Shared caches
/// prefer `s-maxage`; explicit expiration precedes the conservative
/// Last-Modified heuristic.
pub fn calculate_freshness_lifetime(
  response : ResponseMeta,
  options : CacheOptions,
) -> FreshnessCalculation {
  let directives = cache_control_from_headers(response.headers)
  let date_value = response_date_or_time(response)
  let expires_value = parsed_header_date(response.headers, "expires")
  let last_modified_value = parsed_header_date(
    response.headers,
    "last-modified",
  )
  if options.mode is Shared && directives.shared_max_age is Some(delta) {
    return FreshnessCalculation::{
      lifetime: delta,
      source: SharedMaxAge,
      date_value,
      expires_value,
      last_modified_value,
    }
  }
  if directives.max_age is Some(delta) {
    return FreshnessCalculation::{
      lifetime: delta,
      source: MaxAge,
      date_value,
      expires_value,
      last_modified_value,
    }
  }
  if response.headers.contains("expires") {
    let lifetime = match expires_value {
      Some(expires) => expires.elapsed_since(date_value)
      None => DeltaSeconds::zero()
    }
    return FreshnessCalculation::{
      lifetime,
      source: Expires,
      date_value,
      expires_value,
      last_modified_value,
    }
  }
  if options.allow_heuristic_freshness &&
    last_modified_value is Some(last_modified) {
    let resource_age = date_value.elapsed_since(last_modified)
    let fraction = options.heuristic_fraction_per_mille
    let numerator : Int64 = if fraction <= 0 { 0 } else { fraction.to_int64() }
    let lifetime = resource_age
      .saturating_scale(numerator, 1_000)
      .min(options.max_heuristic_lifetime)
    return FreshnessCalculation::{
      lifetime,
      source: HeuristicLastModified,
      date_value,
      expires_value,
      last_modified_value,
    }
  }
  FreshnessCalculation::{
    lifetime: DeltaSeconds::zero(),
    source: NoFreshness,
    date_value,
    expires_value,
    last_modified_value,
  }
}
