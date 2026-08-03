///|
/// The primary lookup key. `GET` and `HEAD` compatibility is applied by the
/// variant module when constructing this value.
pub(all) struct PrimaryCacheKey {
  http_method : String
  uri : String
} derive(Eq, Compare, Hash, Debug)

///|
pub fn PrimaryCacheKey::new(
  http_method : String,
  uri : String,
) -> PrimaryCacheKey {
  PrimaryCacheKey::{
    http_method: normalize_method(http_method),
    uri: uri.trim().to_owned(),
  }
}

///|
pub fn PrimaryCacheKey::label(self : PrimaryCacheKey) -> String {
  "\{self.http_method} \{self.uri}"
}

///|
/// An opaque deterministic encoding of the request fields selected by `Vary`.
pub(all) struct VariantKey {
  canonical : String
  label : String
} derive(Eq, Compare, Hash, Debug)

///|
pub fn VariantKey::empty() -> VariantKey {
  VariantKey::{ canonical: "", label: "(default)" }
}

///|
pub fn VariantKey::from_canonical(
  canonical : String,
  label : String,
) -> VariantKey {
  VariantKey::{ canonical, label }
}

///|
pub(all) struct StoredEntry {
  primary_key : PrimaryCacheKey
  variant_key : VariantKey
  request : RequestMeta
  response : ResponseMeta
  body : Bytes
  policy : StoredPolicy
  stored_at : Timestamp
  last_accessed_at : Timestamp
} derive(Eq, Debug)

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
  StoredEntry::{
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
  StoredEntry::{ ..self, last_accessed_at: now }
}
