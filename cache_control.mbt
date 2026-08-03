///|
/// Cache directives used by both request and response policy. Unknown
/// extensions are intentionally ignored; malformed delta-seconds never become
/// permissive values.
pub(all) struct CacheControl {
  mut no_cache : Bool
  mut no_store : Bool
  mut is_private : Bool
  mut is_public : Bool
  mut must_revalidate : Bool
  mut proxy_revalidate : Bool
  mut immutable : Bool
  mut only_if_cached : Bool
  mut max_age : DeltaSeconds?
  mut shared_max_age : DeltaSeconds?
  mut min_fresh : DeltaSeconds?
  mut max_stale : DeltaSeconds?
  mut max_stale_unbounded : Bool
  mut stale_if_error : DeltaSeconds?
  mut stale_while_revalidate : DeltaSeconds?
  mut malformed_delta : Bool
} derive(Eq, Debug)

///|
pub fn CacheControl::new() -> CacheControl {
  CacheControl::{
    no_cache: false,
    no_store: false,
    is_private: false,
    is_public: false,
    must_revalidate: false,
    proxy_revalidate: false,
    immutable: false,
    only_if_cached: false,
    max_age: None,
    shared_max_age: None,
    min_fresh: None,
    max_stale: None,
    max_stale_unbounded: false,
    stale_if_error: None,
    stale_while_revalidate: None,
    malformed_delta: false,
  }
}

///|
fn unquote_directive_value(value : String) -> String {
  let trimmed = value.trim(chars=" \t").to_owned()
  if trimmed.length() >= 2 &&
    trimmed.has_prefix("\"") &&
    trimmed.has_suffix("\"") {
    trimmed.sub(start=1, end=trimmed.length() - 1).to_owned()
  } else {
    trimmed
  }
}

///|
/// Parse an RFC delta-seconds value. Negative, signed, fractional, and malformed
/// values are rejected. Values that fit Int64 are represented without wrapping.
pub fn parse_delta_seconds(value : String) -> DeltaSeconds? {
  let cleaned = unquote_directive_value(value)
  if cleaned == "" || cleaned.has_prefix("-") || cleaned.has_prefix("+") {
    return None
  }
  for ch in cleaned {
    if ch < '0' || ch > '9' {
      return None
    }
  }
  let parsed : Int64? = Some(@strconv.from_str(cleaned)) catch { _ => None }
  match parsed {
    Some(seconds) => Some(DeltaSeconds::from_seconds(seconds))
    None => None
  }
}

///|
fn minimum_delta(
  current : DeltaSeconds?,
  candidate : DeltaSeconds,
) -> DeltaSeconds {
  match current {
    Some(existing) => existing.min(candidate)
    None => candidate
  }
}

///|
fn parse_directive_delta(
  result : CacheControl,
  raw_value : String?,
) -> DeltaSeconds? {
  match raw_value {
    Some(value) =>
      match parse_delta_seconds(value) {
        Some(delta) => Some(delta)
        None => {
          result.malformed_delta = true
          None
        }
      }
    None => {
      result.malformed_delta = true
      None
    }
  }
}

///|
/// Parse the directive subset needed by MoonCache. Directive names are
/// case-insensitive and repeated numeric directives resolve to the smallest
/// valid value, a conservative deterministic choice.
pub fn parse_cache_control(value : String) -> CacheControl {
  let result = CacheControl::new()
  for part_view in value.split(",") {
    let part = part_view.trim(chars=" \t").to_owned()
    if part == "" {
      continue
    }
    let split = part.split_once("=")
    let name = match split {
      Some((name, _)) => name.trim(chars=" \t").to_lower().to_owned()
      None => part.to_lower()
    }
    let raw_value = match split {
      Some((_, directive_value)) =>
        Some(directive_value.trim(chars=" \t").to_owned())
      None => None
    }
    match name {
      "no-cache" => result.no_cache = true
      "no-store" => result.no_store = true
      "private" => result.is_private = true
      "public" => result.is_public = true
      "must-revalidate" => result.must_revalidate = true
      "proxy-revalidate" => result.proxy_revalidate = true
      "immutable" => result.immutable = true
      "only-if-cached" => result.only_if_cached = true
      "max-age" =>
        match parse_directive_delta(result, raw_value) {
          Some(delta) =>
            result.max_age = Some(minimum_delta(result.max_age, delta))
          None => ()
        }
      "s-maxage" =>
        match parse_directive_delta(result, raw_value) {
          Some(delta) =>
            result.shared_max_age = Some(
              minimum_delta(result.shared_max_age, delta),
            )
          None => ()
        }
      "min-fresh" =>
        match parse_directive_delta(result, raw_value) {
          Some(delta) =>
            result.min_fresh = Some(minimum_delta(result.min_fresh, delta))
          None => ()
        }
      "max-stale" =>
        match raw_value {
          None => result.max_stale_unbounded = true
          Some(_) =>
            match parse_directive_delta(result, raw_value) {
              Some(delta) =>
                result.max_stale = Some(minimum_delta(result.max_stale, delta))
              None => ()
            }
        }
      "stale-if-error" =>
        match parse_directive_delta(result, raw_value) {
          Some(delta) =>
            result.stale_if_error = Some(
              minimum_delta(result.stale_if_error, delta),
            )
          None => ()
        }
      "stale-while-revalidate" =>
        match parse_directive_delta(result, raw_value) {
          Some(delta) =>
            result.stale_while_revalidate = Some(
              minimum_delta(result.stale_while_revalidate, delta),
            )
          None => ()
        }
      _ => ()
    }
  }
  result
}

///|
pub fn cache_control_from_headers(headers : HeaderMap) -> CacheControl {
  parse_cache_control(headers.get("cache-control").unwrap_or(""))
}

///|
/// RFC 9111 retains the older `Pragma: no-cache` request behavior when
/// Cache-Control is absent. This helper keeps that compatibility isolated.
pub fn request_has_legacy_no_cache(headers : HeaderMap) -> Bool {
  if headers.contains("cache-control") {
    return false
  }
  match headers.get("pragma") {
    Some(value) =>
      value
      .split(",")
      .any(fn(part) { part.trim(chars=" \t").to_lower().equal("no-cache") })
    None => false
  }
}
