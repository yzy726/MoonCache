///|
pub(all) struct VarySpec {
  fields : Array[String]
  star : Bool
} derive(Eq, Debug)

///|
pub fn VarySpec::default() -> VarySpec {
  VarySpec::{ fields: [], star: false }
}

///|
fn insert_sorted_unique(values : Array[String], value : String) -> Unit {
  if values.contains(value) {
    return
  }
  let mut index = 0
  while index < values.length() &&
        compare_normalized_header_names(values[index], value) < 0 {
    index = index + 1
  }
  values.insert(index, value)
}

///|
pub fn parse_vary(headers : HeaderMap) -> VarySpec {
  let fields : Array[String] = []
  match headers.get("vary") {
    Some(value) =>
      for part in value.split(",") {
        let field = normalize_header_name(part.to_owned())
        if field == "*" {
          return VarySpec::{ fields: [], star: true }
        }
        if field != "" && is_valid_header_name(field) {
          insert_sorted_unique(fields, field)
        }
      }
    None => ()
  }
  VarySpec::{ fields, star: false }
}

///|
fn encode_vary_field(headers : HeaderMap, name : String) -> (String, String) {
  if !headers.contains(name) {
    return ("\{name.length()}:\{name}=M;", "\{name}=<missing>")
  }
  let values = headers.get_all(name)
  let encoded_values : Array[String] = []
  for value in values {
    encoded_values.push("\{value.length()}:\{value}")
  }
  let encoded = encoded_values.join("")
  let display = values.join(", ")
  (
    "\{name.length()}:\{name}=P\{values.length()}:\{encoded};",
    "\{name}=\{display}",
  )
}

///|
/// Build an opaque length-prefixed key so missing, empty, repeated, and
/// delimiter-containing values cannot collide.
pub fn build_variant_key(headers : HeaderMap, vary : VarySpec) -> VariantKey? {
  if vary.star {
    return None
  }
  if vary.fields.length() == 0 {
    return Some(VariantKey::empty())
  }
  let canonical_parts : Array[String] = []
  let labels : Array[String] = []
  for field in vary.fields {
    let encoded = encode_vary_field(headers, field)
    canonical_parts.push(encoded.0)
    labels.push(encoded.1)
  }
  Some(VariantKey::from_canonical(canonical_parts.join(""), labels.join(" | ")))
}

///|
pub(all) enum VaryMatchKind {
  VaryMatchedResult
  VaryMismatchResult
  VaryStarResult
} derive(Eq, Compare, Debug)

///|
pub(all) struct VaryMatch {
  kind : VaryMatchKind
  differing_field : String?
  stored_key : VariantKey?
  candidate_key : VariantKey?
  reason : CacheReason
} derive(Eq, Debug)

///|
pub fn match_vary(
  stored_request : RequestMeta,
  candidate_request : RequestMeta,
  stored_response : ResponseMeta,
) -> VaryMatch {
  let vary = parse_vary(stored_response.headers)
  if vary.star {
    return VaryMatch::{
      kind: VaryStarResult,
      differing_field: None,
      stored_key: None,
      candidate_key: None,
      reason: CacheReason::with_rfc(VaryStar, "RFC9111-4.1"),
    }
  }
  let stored_key = build_variant_key(stored_request.headers, vary)
  let candidate_key = build_variant_key(candidate_request.headers, vary)
  if stored_key == candidate_key {
    return VaryMatch::{
      kind: VaryMatchedResult,
      differing_field: None,
      stored_key,
      candidate_key,
      reason: CacheReason::with_rfc(
        if vary.fields.length() == 0 {
          VaryDefault
        } else {
          VaryMatched
        },
        "RFC9111-4.1",
      ),
    }
  }
  let mut differing_field : String? = None
  let mut missing_difference = false
  for field in vary.fields {
    let stored_present = stored_request.headers.contains(field)
    let candidate_present = candidate_request.headers.contains(field)
    if stored_present != candidate_present {
      differing_field = Some(field)
      missing_difference = true
      break
    }
    if stored_request.headers.get_all(field) !=
      candidate_request.headers.get_all(field) {
      differing_field = Some(field)
      break
    }
  }
  VaryMatch::{
    kind: VaryMismatchResult,
    differing_field,
    stored_key,
    candidate_key,
    reason: CacheReason::with_rfc(
      if missing_difference {
        VaryMissing
      } else {
        VaryMismatch
      },
      "RFC9111-4.1",
    ),
  }
}

///|
pub(all) struct VariantSelection {
  entry : StoredEntry?
  inspected : Int
  variant_key : VariantKey?
  reasons : Array[CacheReason]
} derive(Eq, Debug)

///|
/// Select the newest matching entry. Equal timestamps keep the store's
/// deterministic iteration order.
pub fn select_variant(
  entries : Array[StoredEntry],
  request : RequestMeta,
) -> VariantSelection {
  let mut selected : StoredEntry? = None
  let mut selected_key : VariantKey? = None
  let reasons : Array[CacheReason] = []
  for entry in entries {
    let result = match_vary(entry.request, request, entry.response)
    reasons.push(result.reason)
    if result.kind is VaryMatchedResult {
      match selected {
        Some(existing) =>
          if entry.stored_at > existing.stored_at {
            selected = Some(entry)
            selected_key = result.candidate_key
          }
        None => {
          selected = Some(entry)
          selected_key = result.candidate_key
        }
      }
    }
  }
  VariantSelection::{
    entry: selected,
    inspected: entries.length(),
    variant_key: selected_key,
    reasons,
  }
}
