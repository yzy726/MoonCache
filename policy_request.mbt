///|
pub(all) struct RequestPolicy {
  bypass : Bool
  force_revalidation : Bool
  only_if_cached : Bool
  max_age : DeltaSeconds?
  min_fresh : DeltaSeconds
  max_stale : DeltaSeconds?
  max_stale_unbounded : Bool
} derive(Eq, Debug)

///|
pub fn evaluate_request_policy(request : RequestMeta) -> RequestPolicy {
  let directives = cache_control_from_headers(request.headers)
  RequestPolicy::{
    bypass: directives.no_store,
    force_revalidation: directives.no_cache ||
    request_has_legacy_no_cache(request.headers),
    only_if_cached: directives.only_if_cached,
    max_age: directives.max_age,
    min_fresh: directives.min_fresh.unwrap_or(DeltaSeconds::zero()),
    max_stale: directives.max_stale,
    max_stale_unbounded: directives.max_stale_unbounded,
  }
}

///|
pub fn RequestPolicy::allows_stale(
  self : RequestPolicy,
  stale_by : DeltaSeconds,
) -> Bool {
  self.max_stale_unbounded ||
  (match self.max_stale {
    Some(limit) => stale_by <= limit
    None => false
  })
}
