///|
pub(all) struct CacheDecision {
  action : CacheActionKind
  trace : CacheTrace
  storage : StorageDecision
} derive(Eq, Debug)

///|
fn add_request_policy_reasons(
  trace : CacheTrace,
  policy : RequestPolicy,
) -> Unit {
  if policy.bypass {
    trace.add_reason(CacheReason::with_rfc(RequestNoStore, "RFC9111-5.2.1.5"))
  }
  if policy.force_revalidation {
    trace.add_reason(CacheReason::with_rfc(RequestNoCache, "RFC9111-5.2.1.4"))
  }
  if policy.only_if_cached {
    trace.add_reason(
      CacheReason::with_rfc(RequestOnlyIfCached, "RFC9111-5.2.1.7"),
    )
  }
  if policy.max_age is Some(_) {
    trace.add_reason(CacheReason::new(RequestMaxAge))
  }
  if policy.min_fresh.seconds() > 0 {
    trace.add_reason(CacheReason::new(RequestMinFresh))
  }
  if policy.max_stale is Some(_) || policy.max_stale_unbounded {
    trace.add_reason(CacheReason::new(RequestMaxStale))
  }
}

///|
fn response_has_validator(response : ResponseMeta) -> Bool {
  response.headers.contains("etag") ||
  response.headers.contains("last-modified")
}

///|
fn decision_with_action(
  action : CacheActionKind,
  trace : CacheTrace,
  storage : StorageDecision,
  reason : CacheReasonCode,
) -> CacheDecision {
  trace.action = action
  trace.add_reason(CacheReason::new(reason))
  CacheDecision::{ action, trace, storage }
}

///|
/// Evaluate one matching cached response at the injected time. Variant lookup
/// and conditional header generation are layered on this deterministic policy
/// function.
pub fn evaluate_cached_response(
  request : RequestMeta,
  response : ResponseMeta,
  options : CacheOptions,
  now : Timestamp,
) -> CacheDecision {
  let request_policy = evaluate_request_policy(request)
  let storage = evaluate_storage(request, response, options)
  let trace = CacheTrace::new(Fetch)
  add_request_policy_reasons(trace, request_policy)
  if request_policy.bypass {
    return decision_with_action(Bypass, trace, storage, RuntimeBypass)
  }
  if !storage.storable {
    for reason in storage.reasons {
      trace.add_reason(reason)
    }
    if request_policy.only_if_cached {
      return decision_with_action(
        OnlyIfCachedMiss,
        trace,
        storage,
        RuntimeOnlyIfCachedMiss,
      )
    }
    return decision_with_action(Fetch, trace, storage, RuntimeFetch)
  }
  let age = calculate_current_age(response, now)
  let freshness = calculate_freshness_lifetime(response, options)
  let response_directives = cache_control_from_headers(response.headers)
  let effective_lifetime = match request_policy.max_age {
    Some(max_age) => freshness.lifetime.min(max_age)
    None => freshness.lifetime
  }
  let required_age = age.current_age.saturating_add(request_policy.min_fresh)
  let is_fresh = required_age < effective_lifetime
  let force_revalidation = request_policy.force_revalidation ||
    response_directives.no_cache
  let stale_by = age.current_age.saturating_sub(effective_lifetime)
  trace.age = Some(age)
  trace.freshness_lifetime = Some(effective_lifetime)
  trace.add_reason(CacheReason::with_rfc(AgeCorrected, "RFC9111-4.2.3"))
  if age.clock_clamped {
    trace.add_reason(CacheReason::new(AgeClockClamped))
  }
  if age.overflow_clamped {
    trace.add_reason(CacheReason::new(AgeOverflowClamped))
  }
  trace.add_reason(CacheReason::new(freshness.source.reason()))
  if is_fresh && !force_revalidation {
    trace.add_reason(CacheReason::with_rfc(FreshStillFresh, "RFC9111-4.2"))
    return decision_with_action(ServeFresh, trace, storage, RuntimeHit)
  }
  if !is_fresh {
    trace.stale_by = Some(stale_by)
    trace.add_reason(CacheReason::with_rfc(FreshStale, "RFC9111-4.2"))
  }
  let stale_forbidden = response_directives.must_revalidate ||
    (options.mode is Shared && response_directives.proxy_revalidate) ||
    force_revalidation
  if !is_fresh && !stale_forbidden && request_policy.allows_stale(stale_by) {
    return decision_with_action(ServeStale, trace, storage, RuntimeHit)
  }
  if request_policy.only_if_cached {
    return decision_with_action(
      OnlyIfCachedMiss,
      trace,
      storage,
      RuntimeOnlyIfCachedMiss,
    )
  }
  if response_has_validator(response) {
    decision_with_action(Revalidate, trace, storage, RevalidateEtag)
  } else {
    decision_with_action(Fetch, trace, storage, RuntimeFetch)
  }
}
