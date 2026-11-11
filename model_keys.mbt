///|
/// The primary lookup key. `GET` and `HEAD` compatibility is applied by the
/// variant module when constructing this value.
#derive(Eq, Compare, Hash, Debug)
pub(all) struct PrimaryCacheKey {
  http_method : String
  uri : String
}

///|
pub fn PrimaryCacheKey::new(
  http_method : String,
  uri : String,
) -> PrimaryCacheKey {
  { http_method: normalize_method(http_method), uri: uri.trim().to_owned(), }
}

///|
pub fn PrimaryCacheKey::label(self : PrimaryCacheKey) -> String {
  "\{self.http_method} \{self.uri}"
}

///|
/// An opaque deterministic encoding of the request fields selected by `Vary`.
#derive(Eq, Compare, Hash, Debug)
pub(all) struct VariantKey {
  canonical : String
  label : String
}

///|
pub fn VariantKey::empty() -> VariantKey {
  { canonical: "", label: "(default)", }
}

///|
pub fn VariantKey::from_canonical(
  canonical : String,
  label : String,
) -> VariantKey {
  { canonical, label, }
}

///|
#derive(Eq, Debug)
pub(all) struct StoredEntry {
  primary_key : PrimaryCacheKey
  variant_key : VariantKey
  request : RequestMeta
  response : ResponseMeta
  body : Bytes
  policy : StoredPolicy
  stored_at : Timestamp
  last_accessed_at : Timestamp
}

///|
pub fn StoredEntry::new(
  primary_key : PrimaryCacheKey,
  variant_key : VariantKey,
  request : RequestMeta,
  response : ResponseMeta,
  body : Bytes,
  policy : StoredPolicy,
  stored_at : Timestamp,
) -> StoredEntry {
  {
    primary_key,
    variant_key,
    request,
    response,
    body,
    policy,
    stored_at,
    last_accessed_at: stored_at,
  }
}

///|
pub fn StoredEntry::body_size(self : StoredEntry) -> Int64 {
  self.body.length().to_int64()
}

///|
pub fn StoredEntry::touch(self : StoredEntry, now : Timestamp) -> StoredEntry {
  { ..self, last_accessed_at: now, }
}

///|
/// Deep-copy mutable metadata while sharing the immutable body bytes.
pub fn StoredEntry::copy(self : StoredEntry) -> StoredEntry {
  {
    primary_key: self.primary_key,
    variant_key: self.variant_key,
    request: { ..self.request, headers: self.request.headers.copy(), },
    response: { ..self.response, headers: self.response.headers.copy(), },
    body: self.body,
    policy: self.policy,
    stored_at: self.stored_at,
    last_accessed_at: self.last_accessed_at,
  }
}

///|
pub extend PrimaryCacheKey with @debug.Debug::{to_repr}

///|
pub extend PrimaryCacheKey with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend PrimaryCacheKey with Eq::{not_equal, equal}

///|
pub extend PrimaryCacheKey with Hash::{hash, hash_combine}

///|
pub extend StoredEntry with @debug.Debug::{to_repr}

///|
pub extend StoredEntry with Eq::{not_equal, equal}

///|
pub extend VariantKey with @debug.Debug::{to_repr}

///|
pub extend VariantKey with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend VariantKey with Eq::{not_equal, equal}

///|
pub extend VariantKey with Hash::{hash, hash_combine}
