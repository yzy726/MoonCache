///|
/// Version of the durable metadata format understood by this package.
pub const FILE_STORE_FORMAT_VERSION : Int = 1

///|
priv struct DiskHeaderV1 {
  name : String
  value : String
} derive(FromJson, ToJson)

///|
priv struct DiskPolicyV1 {
  cacheable : Bool
  freshness_lifetime_seconds : Int64
  requires_revalidation : Bool
  no_store : Bool
  vary_star : Bool
  must_revalidate : Bool
  proxy_revalidate : Bool
  is_private : Bool
  is_public : Bool
} derive(FromJson, ToJson)

///|
priv struct DiskEntryV1 {
  format_version : Int
  entry_id : String
  primary_method : String
  primary_uri : String
  variant_canonical : String
  variant_label : String
  request_method : String
  request_uri : String
  request_headers : Array[DiskHeaderV1]
  request_time_seconds : Int64
  response_status : Int
  response_headers : Array[DiskHeaderV1]
  response_request_time_seconds : Int64
  response_time_seconds : Int64
  response_body_complete : Bool
  policy : DiskPolicyV1
  body_digest : String
  body_size : Int64
  stored_at_seconds : Int64
  last_accessed_at_seconds : Int64
} derive(FromJson, ToJson)

///|
priv struct DiskManifestV1 {
  format_version : Int
  generation : Int64
  entry_ids : Array[String]
} derive(FromJson, ToJson)

///|
priv struct DiskIndexV1 {
  format_version : Int
  index_id : String
  primary_method : String
  primary_uri : String
  entry_ids : Array[String]
} derive(FromJson, ToJson)

///|
fn sha256_hex_bytes(content : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(content))
}

///|
fn sha256_hex_text(content : String) -> String {
  sha256_hex_bytes(native_text(content))
}

///|
fn encoded_key_component(label : String, value : String) -> String {
  "\{label}\{value.length()}:\{value};"
}

///|
fn primary_index_id(key : @mooncache.PrimaryCacheKey) -> String {
  sha256_hex_text(
    encoded_key_component("m", key.http_method) +
    encoded_key_component("u", key.uri),
  )
}

///|
pub fn entry_file_id(entry : @mooncache.StoredEntry) -> String {
  sha256_hex_text(
    encoded_key_component("m", entry.primary_key.http_method) +
    encoded_key_component("u", entry.primary_key.uri) +
    encoded_key_component("v", entry.variant_key.canonical),
  )
}

///|
pub fn body_file_digest(body : Bytes) -> String {
  sha256_hex_bytes(body)
}

///|
fn is_lower_hex_digest(value : String) -> Bool {
  if value.length() != 64 {
    return false
  }
  for code_unit in value {
    if !((code_unit >= '0' && code_unit <= '9') ||
      (code_unit >= 'a' && code_unit <= 'f')) {
      return false
    }
  }
  true
}

///|
fn persisted_headers(headers : @mooncache.HeaderMap) -> Array[DiskHeaderV1] {
  headers
  .pairs()
  .map(fn(pair) { DiskHeaderV1::{ name: pair.0, value: pair.1 } })
}

///|
fn persisted_header_bytes(headers : Array[DiskHeaderV1]) -> Int {
  let mut size = 0
  for header in headers {
    size = size +
      native_text(header.name).length() +
      native_text(header.value).length()
  }
  size
}

///|
fn contains_forbidden_header_octet(value : String) -> Bool {
  value.contains("\r") || value.contains("\n") || value.contains("\u0000")
}

///|
fn restore_headers(
  headers : Array[DiskHeaderV1],
  maximum_bytes : Int,
) -> @mooncache.HeaderMap raise FileStoreError {
  guard persisted_header_bytes(headers) <= maximum_bytes else {
    raise FileStoreCorrupt("persisted header block exceeds configured limit")
  }
  let result = @mooncache.HeaderMap::new()
  for header in headers {
    guard !contains_forbidden_header_octet(header.name) &&
      !contains_forbidden_header_octet(header.value) else {
      raise FileStoreCorrupt("persisted header contains a forbidden octet")
    }
    guard result.append(header.name, header.value) else {
      raise FileStoreCorrupt("persisted header name is invalid")
    }
  }
  result
}

///|
fn DiskEntryV1::from_entry(entry : @mooncache.StoredEntry) -> DiskEntryV1 {
  DiskEntryV1::{
    format_version: FILE_STORE_FORMAT_VERSION,
    entry_id: entry_file_id(entry),
    primary_method: entry.primary_key.http_method,
    primary_uri: entry.primary_key.uri,
    variant_canonical: entry.variant_key.canonical,
    variant_label: entry.variant_key.label,
    request_method: entry.request.http_method,
    request_uri: entry.request.uri,
    request_headers: persisted_headers(entry.request.headers),
    request_time_seconds: entry.request.request_time.seconds(),
    response_status: entry.response.status,
    response_headers: persisted_headers(entry.response.headers),
    response_request_time_seconds: entry.response.request_time.seconds(),
    response_time_seconds: entry.response.response_time.seconds(),
    response_body_complete: entry.response.body_complete,
    policy: DiskPolicyV1::{
      cacheable: entry.policy.cacheable,
      freshness_lifetime_seconds: entry.policy.freshness_lifetime.seconds(),
      requires_revalidation: entry.policy.requires_revalidation,
      no_store: entry.policy.no_store,
      vary_star: entry.policy.vary_star,
      must_revalidate: entry.policy.must_revalidate,
      proxy_revalidate: entry.policy.proxy_revalidate,
      is_private: entry.policy.is_private,
      is_public: entry.policy.is_public,
    },
    body_digest: body_file_digest(entry.body),
    body_size: entry.body_size(),
    stored_at_seconds: entry.stored_at.seconds(),
    last_accessed_at_seconds: entry.last_accessed_at.seconds(),
  }
}

///|
fn validate_non_negative_time(value : Int64) -> Bool {
  value >= 0
}

///|
fn DiskEntryV1::to_entry(
  self : DiskEntryV1,
  body : Bytes,
  maximum_header_bytes : Int,
) -> @mooncache.StoredEntry raise FileStoreError {
  guard self.format_version == FILE_STORE_FORMAT_VERSION else {
    raise FileStoreUnsupportedVersion(self.format_version)
  }
  guard is_lower_hex_digest(self.entry_id) else {
    raise FileStoreCorrupt("entry id is not a lowercase SHA-256 digest")
  }
  guard is_lower_hex_digest(self.body_digest) else {
    raise FileStoreCorrupt("body id is not a lowercase SHA-256 digest")
  }
  guard self.body_size >= 0 && self.body_size == body.length().to_int64() else {
    raise FileStoreCorrupt("persisted body length does not match metadata")
  }
  guard body_file_digest(body) == self.body_digest else {
    raise FileStoreCorrupt("persisted body digest does not match metadata")
  }
  guard self.response_status >= 100 && self.response_status <= 599 else {
    raise FileStoreCorrupt("persisted response status is outside HTTP range")
  }
  guard validate_non_negative_time(self.request_time_seconds) &&
    validate_non_negative_time(self.response_request_time_seconds) &&
    validate_non_negative_time(self.response_time_seconds) &&
    validate_non_negative_time(self.stored_at_seconds) &&
    validate_non_negative_time(self.last_accessed_at_seconds) &&
    self.policy.freshness_lifetime_seconds >= 0 else {
    raise FileStoreCorrupt("persisted time value is negative")
  }
  let request_headers = restore_headers(
    self.request_headers,
    maximum_header_bytes,
  )
  let response_headers = restore_headers(
    self.response_headers,
    maximum_header_bytes,
  )
  let request = @mooncache.RequestMeta::new(
    self.request_method,
    self.request_uri,
    request_headers,
    @mooncache.Timestamp::from_seconds(self.request_time_seconds),
  )
  let primary = @mooncache.PrimaryCacheKey::new(
    self.primary_method,
    self.primary_uri,
  )
  guard @mooncache.PrimaryCacheKey::from_request(request) == Some(primary) else {
    raise FileStoreCorrupt(
      "persisted primary key does not match request method and URI",
    )
  }
  let variant = @mooncache.VariantKey::from_canonical(
    self.variant_canonical,
    self.variant_label,
  )
  let response = @mooncache.ResponseMeta::new(
    self.response_status,
    response_headers,
    @mooncache.Timestamp::from_seconds(self.response_request_time_seconds),
    @mooncache.Timestamp::from_seconds(self.response_time_seconds),
    self.response_body_complete,
  )
  let vary = @mooncache.parse_vary(response.headers)
  guard @mooncache.build_variant_key(request.headers, vary) == Some(variant) else {
    raise FileStoreCorrupt(
      "persisted variant key does not match request and Vary metadata",
    )
  }
  let policy = @mooncache.StoredPolicy::{
    cacheable: self.policy.cacheable,
    freshness_lifetime: @mooncache.DeltaSeconds::from_seconds(
      self.policy.freshness_lifetime_seconds,
    ),
    requires_revalidation: self.policy.requires_revalidation,
    no_store: self.policy.no_store,
    vary_star: self.policy.vary_star,
    must_revalidate: self.policy.must_revalidate,
    proxy_revalidate: self.policy.proxy_revalidate,
    is_private: self.policy.is_private,
    is_public: self.policy.is_public,
  }
  let entry = @mooncache.StoredEntry::new(
    primary,
    variant,
    request,
    response,
    body,
    policy,
    @mooncache.Timestamp::from_seconds(self.stored_at_seconds),
  )
  let restored = @mooncache.StoredEntry::{
    ..entry,
    last_accessed_at: @mooncache.Timestamp::from_seconds(
      self.last_accessed_at_seconds,
    ),
  }
  guard entry_file_id(restored) == self.entry_id else {
    raise FileStoreCorrupt("persisted entry id does not match cache key")
  }
  restored
}

///|
fn encode_entry_metadata(entry : @mooncache.StoredEntry) -> String {
  ToJson::to_json(DiskEntryV1::from_entry(entry)).stringify(indent=2)
}

///|
fn decode_entry_metadata(text : String) -> DiskEntryV1 raise FileStoreError {
  let json = @json.parse(text) catch {
    error => raise FileStoreCorrupt("metadata JSON parse failed: \{error}")
  }
  @json.from_json(json) catch {
    error => raise FileStoreCorrupt("metadata schema decode failed: \{error}")
  }
}

///|
fn encode_manifest(manifest : DiskManifestV1) -> String {
  ToJson::to_json(manifest).stringify(indent=2)
}

///|
fn decode_manifest(text : String) -> DiskManifestV1 raise FileStoreError {
  let json = @json.parse(text) catch {
    error =>
      raise FileStoreCorrupt("store manifest JSON parse failed: \{error}")
  }
  @json.from_json(json) catch {
    error =>
      raise FileStoreCorrupt("store manifest schema decode failed: \{error}")
  }
}

///|
fn encode_index(index : DiskIndexV1) -> String {
  ToJson::to_json(index).stringify(indent=2)
}

///|
fn decode_index(text : String) -> DiskIndexV1 raise FileStoreError {
  let json = @json.parse(text) catch {
    error => raise FileStoreCorrupt("store index JSON parse failed: \{error}")
  }
  @json.from_json(json) catch {
    error =>
      raise FileStoreCorrupt("store index schema decode failed: \{error}")
  }
}
