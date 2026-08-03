///|
pub(all) enum ValidatorKind {
  StrongEtag
  WeakEtag
  LastModified
  StrongEtagAndLastModified
  WeakEtagAndLastModified
  CallerConditions
} derive(Eq, Compare, Debug)

///|
pub fn ValidatorKind::label(self : ValidatorKind) -> String {
  match self {
    StrongEtag => "strong-etag"
    WeakEtag => "weak-etag"
    LastModified => "last-modified"
    StrongEtagAndLastModified => "strong-etag + last-modified"
    WeakEtagAndLastModified => "weak-etag + last-modified"
    CallerConditions => "caller-conditions"
  }
}

///|
fn etag_is_weak(value : String) -> Bool {
  value.has_prefix("W/")
}

///|
pub fn is_valid_etag(value : String) -> Bool {
  let tag = value.trim(chars=" \t").to_owned()
  let tag_text = if tag.has_prefix("W/") {
    tag.sub(start=2).to_owned()
  } else {
    tag
  }
  if tag_text.length() < 2 ||
    !tag_text.has_prefix("\"") ||
    !tag_text.has_suffix("\"") {
    return false
  }
  let inside = tag_text.sub(start=1, end=tag_text.length() - 1).to_owned()
  !inside.contains("\"") && !inside.contains("\r") && !inside.contains("\n")
}

///|
fn valid_last_modified(value : String) -> Bool {
  parse_http_date(value) is Some(_)
}

///|
pub fn response_validator_kind(response : ResponseMeta) -> ValidatorKind? {
  let etag = match response.headers.get_first("etag") {
    Some(value) => if is_valid_etag(value) { Some(value) } else { None }
    None => None
  }
  let last_modified = match response.headers.get_first("last-modified") {
    Some(value) => if valid_last_modified(value) { Some(value) } else { None }
    None => None
  }
  match (etag, last_modified) {
    (Some(tag), Some(_)) =>
      if etag_is_weak(tag) {
        Some(WeakEtagAndLastModified)
      } else {
        Some(StrongEtagAndLastModified)
      }
    (Some(tag), None) =>
      if etag_is_weak(tag) {
        Some(WeakEtag)
      } else {
        Some(StrongEtag)
      }
    (None, Some(_)) => Some(LastModified)
    (None, None) => None
  }
}

///|
pub fn has_usable_validator(response : ResponseMeta) -> Bool {
  response_validator_kind(response) is Some(_)
}

///|
pub(all) struct RevalidationPlan {
  request : RequestMeta
  generated_headers : HeaderMap
  validator_kind : ValidatorKind?
  reasons : Array[CacheReason]
} derive(Eq, Debug)

///|
pub fn RevalidationPlan::can_revalidate(self : RevalidationPlan) -> Bool {
  self.request.headers.contains("if-none-match") ||
  self.request.headers.contains("if-modified-since")
}

///|
/// Generate conditional fields without replacing conditions supplied by the
/// caller. Strong and weak ETags are both valid for If-None-Match.
pub fn create_revalidation_plan(
  request : RequestMeta,
  stored_response : ResponseMeta,
) -> RevalidationPlan {
  let headers = request.headers.copy()
  let generated = HeaderMap::new()
  let reasons : Array[CacheReason] = []
  let caller_has_etag = headers.contains("if-none-match")
  let caller_has_date = headers.contains("if-modified-since")
  if caller_has_etag || caller_has_date {
    reasons.push(
      CacheReason::with_rfc(RevalidateCallerCondition, "RFC9111-4.3.2"),
    )
  }
  let mut added_etag : String? = None
  let mut added_date = false
  if !caller_has_etag {
    match stored_response.headers.get_first("etag") {
      Some(value) =>
        if is_valid_etag(value) {
          ignore(headers.set("if-none-match", value))
          ignore(generated.set("if-none-match", value))
          added_etag = Some(value)
          reasons.push(CacheReason::with_rfc(RevalidateEtag, "RFC9111-4.3.2"))
        }
      None => ()
    }
  }
  if !caller_has_date {
    match stored_response.headers.get_first("last-modified") {
      Some(value) =>
        if valid_last_modified(value) {
          ignore(headers.set("if-modified-since", value))
          ignore(generated.set("if-modified-since", value))
          added_date = true
          reasons.push(
            CacheReason::with_rfc(RevalidateLastModified, "RFC9111-4.3.2"),
          )
        }
      None => ()
    }
  }
  let validator_kind = match (added_etag, added_date) {
    (Some(tag), true) => {
      reasons.push(CacheReason::new(RevalidateBoth))
      if etag_is_weak(tag) {
        Some(WeakEtagAndLastModified)
      } else {
        Some(StrongEtagAndLastModified)
      }
    }
    (Some(tag), false) =>
      if etag_is_weak(tag) {
        Some(WeakEtag)
      } else {
        Some(StrongEtag)
      }
    (None, true) => Some(LastModified)
    (None, false) =>
      if caller_has_etag || caller_has_date {
        Some(CallerConditions)
      } else {
        None
      }
  }
  RevalidationPlan::{
    request: request.with_headers(headers),
    generated_headers: generated,
    validator_kind,
    reasons,
  }
}

///|
pub suberror ValidationError {
  ExpectedNotModified(Int)
} derive(Eq, Debug)

///|
pub fn ValidationError::message(self : ValidationError) -> String {
  match self {
    ExpectedNotModified(status) => "expected status 304, received \{status}"
  }
}

///|
fn connection_named_fields(headers : HeaderMap) -> Array[String] {
  let result : Array[String] = []
  match headers.get("connection") {
    Some(value) =>
      for part in value.split(",") {
        let name = normalize_header_name(part.to_owned())
        if name != "" && !result.contains(name) {
          result.push(name)
        }
      }
    None => ()
  }
  result
}

///|
fn forbidden_304_merge_field(
  name : String,
  connection_fields : Array[String],
) -> Bool {
  name == "connection" ||
  name == "keep-alive" ||
  name == "proxy-authenticate" ||
  name == "proxy-authorization" ||
  name == "te" ||
  name == "trailer" ||
  name == "transfer-encoding" ||
  name == "upgrade" ||
  name == "content-length" ||
  connection_fields.contains(name)
}

///|
fn replace_header_values(
  target : HeaderMap,
  name : String,
  values : Array[String],
) -> Unit {
  if values.length() == 0 {
    return
  }
  ignore(target.set(name, values[0]))
  for index = 1; index < values.length(); index = index + 1 {
    ignore(target.append(name, values[index]))
  }
}

///|
fn merged_304_headers(
  cached : HeaderMap,
  not_modified : HeaderMap,
) -> HeaderMap {
  let result = cached.copy()
  ignore(result.remove("warning"))
  let connection_fields = connection_named_fields(not_modified)
  for name in not_modified.names() {
    if !forbidden_304_merge_field(name, connection_fields) {
      replace_header_values(result, name, not_modified.get_all(name))
    }
  }
  result
}

///|
pub(all) struct NotModifiedResult {
  entry : StoredEntry
  storage : StorageDecision
  reasons : Array[CacheReason]
} derive(Eq, Debug)

///|
/// Merge a 304 response into a stored entry while retaining the cached status
/// and body, then recompute cacheability, freshness, and variant identity.
pub fn merge_not_modified(
  entry : StoredEntry,
  not_modified : ResponseMeta,
  options : CacheOptions,
  now : Timestamp,
) -> NotModifiedResult raise ValidationError {
  if not_modified.status != 304 {
    raise ExpectedNotModified(not_modified.status)
  }
  let headers = merged_304_headers(entry.response.headers, not_modified.headers)
  let response = ResponseMeta::new(
    entry.response.status,
    headers,
    not_modified.request_time,
    not_modified.response_time,
    entry.response.body_complete,
  )
  let storage = evaluate_storage(entry.request, response, options)
  let variant = build_variant_key(entry.request.headers, parse_vary(headers)).unwrap_or(
    entry.variant_key,
  )
  let merged = StoredEntry::{
    primary_key: entry.primary_key,
    variant_key: variant,
    request: entry.request,
    response,
    body: entry.body,
    policy: storage.policy,
    stored_at: now,
    last_accessed_at: now,
  }
  let reasons : Array[CacheReason] = [
    CacheReason::with_rfc(RevalidateNotModified, "RFC9111-4.3.4"),
  ]
  reasons.push_iter(storage.reasons.iter())
  NotModifiedResult::{ entry: merged, storage, reasons }
}
