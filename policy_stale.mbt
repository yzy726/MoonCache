///|
/// Evaluation of RFC 5861 stale extensions for one stored response.
pub(all) struct StalePolicy {
  is_stale : Bool
  stale_by : DeltaSeconds
  stale_if_error_window : DeltaSeconds?
  stale_while_revalidate_window : DeltaSeconds?
  stale_if_error_allowed : Bool
  stale_while_revalidate_allowed : Bool
  prohibited : Bool
} derive(Eq, Debug)

///|
fn minimum_optional_window(
  first : DeltaSeconds?,
  second : DeltaSeconds?,
) -> DeltaSeconds? {
  match (first, second) {
    (Some(left), Some(right)) => Some(left.min(right))
    (Some(value), None) | (None, Some(value)) => Some(value)
    (None, None) => None
  }
}

///|
/// Evaluate origin- and client-provided stale permissions without performing
/// I/O. Explicit revalidation requirements remain stronger than extensions.
pub fn evaluate_stale_policy(
  request : RequestMeta,
  response : ResponseMeta,
  options : CacheOptions,
  now : Timestamp,
) -> StalePolicy {
  let request_policy = evaluate_request_policy(request)
  let request_directives = cache_control_from_headers(request.headers)
  let response_directives = cache_control_from_headers(response.headers)
  let age = calculate_current_age(response, now)
  let freshness = calculate_freshness_lifetime(response, options)
  let is_stale = age.current_age >= freshness.lifetime
  let stale_by = age.current_age.saturating_sub(freshness.lifetime)
  let stale_if_error_window = minimum_optional_window(
    request_directives.stale_if_error,
    response_directives.stale_if_error,
  )
  let stale_while_revalidate_window = response_directives.stale_while_revalidate
  let prohibited = request_policy.bypass ||
    request_policy.force_revalidation ||
    request_policy.only_if_cached ||
    response_directives.no_cache ||
    response_directives.must_revalidate ||
    (options.mode is Shared && response_directives.proxy_revalidate)
  StalePolicy::{
    is_stale,
    stale_by,
    stale_if_error_window,
    stale_while_revalidate_window,
    stale_if_error_allowed: is_stale &&
    !prohibited &&
    (match stale_if_error_window {
      Some(window) => stale_by <= window
      None => false
    }),
    stale_while_revalidate_allowed: is_stale &&
    !prohibited &&
    (match stale_while_revalidate_window {
      Some(window) => stale_by <= window
      None => false
    }),
    prohibited,
  }
}

///|
/// RFC 5861 defines these statuses as errors eligible for stale-if-error.
pub fn is_stale_if_error_status(status : Int) -> Bool {
  status == 500 || status == 502 || status == 503 || status == 504
}
