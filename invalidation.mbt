///|
pub fn is_safe_http_method(http_method : String) -> Bool {
  let normalized = normalize_method(http_method)
  normalized == "GET" ||
  normalized == "HEAD" ||
  normalized == "OPTIONS" ||
  normalized == "TRACE"
}

///|
fn base_without_query(uri : String) -> String {
  match uri.split_once("?") {
    Some((base, _)) => base.to_owned()
    None => uri
  }
}

///|
/// Resolve the absolute and relative URI forms used by Location and
/// Content-Location for invalidation.
pub fn resolve_related_uri(base : String, reference : String) -> String? {
  let trimmed = reference.trim(chars=" \t").to_owned()
  guard normalize_cache_uri(base) is Some(normalized_base) else { return None }
  if trimmed == "" {
    return Some(normalized_base)
  }
  if trimmed.has_prefix("http://") || trimmed.has_prefix("https://") {
    return normalize_cache_uri(trimmed)
  }
  guard cache_origin(normalized_base) is Some(origin) else { return None }
  if trimmed.has_prefix("/") {
    return normalize_cache_uri("\{origin}\{trimmed}")
  }
  let base_path = base_without_query(normalized_base)
  if trimmed.has_prefix("?") {
    return normalize_cache_uri("\{base_path}\{trimmed}")
  }
  let directory = match base_path.rev_split_once("/") {
    Some((before, _)) => "\{before.to_owned()}/"
    None => "\{origin}/"
  }
  normalize_cache_uri("\{directory}\{trimmed}")
}

///|
fn append_unique_uri(uris : Array[String], uri : String) -> Bool {
  if uris.contains(uri) {
    false
  } else {
    uris.push(uri)
    true
  }
}

///|
pub(all) struct InvalidationPlan {
  uris : Array[String]
  reasons : Array[CacheReason]
} derive(Eq, Debug)

///|
/// RFC 9111 invalidation plan for a non-error response to an unsafe method.
/// Related targets are included only when their resolved URI has the same
/// origin as the request target.
pub fn plan_invalidation(
  request : RequestMeta,
  response : ResponseMeta,
) -> InvalidationPlan {
  let uris : Array[String] = []
  let reasons : Array[CacheReason] = []
  if is_safe_http_method(request.http_method) {
    reasons.push(
      CacheReason::with_rfc(InvalidateSkippedSafeMethod, "RFC9111-4.4"),
    )
    return InvalidationPlan::{ uris, reasons }
  }
  if response.status < 200 || response.status >= 400 {
    reasons.push(
      CacheReason::with_rfc(InvalidateSkippedErrorStatus, "RFC9111-4.4"),
    )
    return InvalidationPlan::{ uris, reasons }
  }
  match normalize_cache_uri(request.uri) {
    Some(target) => {
      ignore(append_unique_uri(uris, target))
      reasons.push(CacheReason::with_rfc(InvalidateUnsafeMethod, "RFC9111-4.4"))
      for name in ["location", "content-location"] {
        match response.headers.get_first(name) {
          Some(reference) =>
            match resolve_related_uri(target, reference) {
              Some(related) =>
                if same_cache_origin(target, related) &&
                  append_unique_uri(uris, related) {
                  reasons.push(
                    CacheReason::with_detail(
                      InvalidateRelatedUri,
                      "\{name}: \{related}",
                    ),
                  )
                }
              None => ()
            }
          None => ()
        }
      }
    }
    None => ()
  }
  InvalidationPlan::{ uris, reasons }
}
