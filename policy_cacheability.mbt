///|
pub(all) struct StorageDecision {
  storable : Bool
  policy : StoredPolicy
  reasons : Array[CacheReason]
} derive(Eq, Debug)

///|
fn rejected_storage(code : CacheReasonCode, rfc : String) -> StorageDecision {
  StorageDecision::{
    storable: false,
    policy: StoredPolicy::uncacheable(),
    reasons: [CacheReason::with_rfc(code, rfc)],
  }
}

///|
/// Statuses defined as heuristically cacheable by RFC 9111. Partial-content
/// status 206 is excluded because range caching is outside the 0.1.3 scope.
pub fn is_default_cacheable_status(status : Int) -> Bool {
  status == 200 ||
  status == 203 ||
  status == 204 ||
  status == 300 ||
  status == 301 ||
  status == 308 ||
  status == 404 ||
  status == 405 ||
  status == 410 ||
  status == 414 ||
  status == 501
}

///|
fn has_vary_star(headers : HeaderMap) -> Bool {
  match headers.get("vary") {
    Some(value) =>
      value.split(",").any(fn(part) { part.trim(chars=" \t").equal("*") })
    None => false
  }
}

///|
fn has_explicit_expiration(
  response : ResponseMeta,
  directives : CacheControl,
) -> Bool {
  directives.max_age is Some(_) ||
  directives.shared_max_age is Some(_) ||
  directives.is_public ||
  response.headers.contains("expires")
}

///|
fn shared_authorization_permitted(
  request : RequestMeta,
  directives : CacheControl,
  options : CacheOptions,
) -> Bool {
  !request.headers.contains("authorization") ||
  options.allow_shared_authorized ||
  directives.is_public ||
  directives.shared_max_age is Some(_) ||
  directives.must_revalidate ||
  directives.proxy_revalidate
}

///|
/// Decide whether a complete response may enter the selected cache mode.
pub fn evaluate_storage(
  request : RequestMeta,
  response : ResponseMeta,
  options : CacheOptions,
) -> StorageDecision {
  let request_directives = cache_control_from_headers(request.headers)
  let response_directives = cache_control_from_headers(response.headers)
  if request.http_method != "GET" && request.http_method != "HEAD" {
    return rejected_storage(StoreMethodUnsupported, "RFC9111-3")
  }
  if request.http_method == "HEAD" && !options.cache_head_responses {
    return rejected_storage(StoreMethodUnsupported, "RFC9111-3")
  }
  if request_directives.no_store || response_directives.no_store {
    return rejected_storage(StoreNoStore, "RFC9111-5.2.2.5")
  }
  if !response.body_complete {
    return rejected_storage(StoreIncomplete, "RFC9111-3")
  }
  if has_vary_star(response.headers) {
    return rejected_storage(StoreVaryStar, "RFC9111-4.1")
  }
  if options.mode is Shared && response_directives.is_private {
    return rejected_storage(StorePrivateShared, "RFC9111-5.2.2.7")
  }
  if options.mode is Shared &&
    !shared_authorization_permitted(request, response_directives, options) {
    return rejected_storage(StoreAuthorizationShared, "RFC9111-3.2")
  }
  if response.status < 100 || response.status > 599 || response.status == 206 {
    return rejected_storage(StoreStatusUnknown, "RFC9111-3")
  }
  let default_status = is_default_cacheable_status(response.status)
  let explicit = has_explicit_expiration(response, response_directives)
  if !default_status && !explicit {
    return rejected_storage(StoreStatusUnknown, "RFC9111-3")
  }
  let freshness = calculate_freshness_lifetime(response, options)
  let reasons : Array[CacheReason] = [
    CacheReason::with_rfc(StoreAllowed, "RFC9111-3"),
  ]
  if default_status {
    reasons.push(CacheReason::with_rfc(StoreStatusDefault, "RFC9111-3"))
  } else {
    reasons.push(CacheReason::with_rfc(StoreStatusExplicit, "RFC9111-3"))
  }
  reasons.push(CacheReason::new(freshness.source.reason()))
  StorageDecision::{
    storable: true,
    policy: StoredPolicy::from_directives(
      freshness.lifetime,
      response_directives,
      false,
    ),
    reasons,
  }
}
