///|
pub(all) struct MemoryStoreOptions {
  max_entries : Int
  max_body_bytes : Int64
  max_body_size : Int64
  strip_set_cookie : Bool
  strip_request_credentials : Bool
} derive(Eq, Debug)

///|
pub fn MemoryStoreOptions::default() -> MemoryStoreOptions {
  MemoryStoreOptions::{
    max_entries: 256,
    max_body_bytes: 64 * 1_024 * 1_024,
    max_body_size: 8 * 1_024 * 1_024,
    strip_set_cookie: true,
    strip_request_credentials: true,
  }
}

///|
pub fn MemoryStoreOptions::with_limits(
  max_entries : Int,
  max_body_bytes : Int64,
  max_body_size : Int64,
) -> MemoryStoreOptions {
  MemoryStoreOptions::{
    ..MemoryStoreOptions::default(),
    max_entries,
    max_body_bytes,
    max_body_size,
  }
}

///|
pub(all) enum StorePutResult {
  StoreInserted
  StoreReplacedResult
  StoreRejectedNoStore
  StoreRejectedOversized
  StoreRejectedCapacity
} derive(Eq, Compare, Debug)

///|
pub(all) struct StoreStats {
  entries : Int
  body_bytes : Int64
  puts : Int64
  replacements : Int64
  evictions : Int64
  lookups : Int64
  hits : Int64
  misses : Int64
  invalidated_entries : Int64
  rejected_entries : Int64
} derive(Eq, Debug)

///|
pub(open) trait CacheStore {
  fn find_variants(Self, PrimaryCacheKey) -> Array[StoredEntry]
  fn put(Self, StoredEntry) -> StorePutResult
  fn remove_variant(Self, PrimaryCacheKey, VariantKey) -> Bool
  fn invalidate_uri(Self, String) -> Int
  fn clear(Self) -> Unit
  fn stats(Self) -> StoreStats
}

///|
priv struct StoreRecord {
  entry : StoredEntry
  mut access_order : Int64
  insertion_order : Int64
}

///|
/// HTTP-specific in-memory store with deterministic logical access ordering.
pub struct MemoryStore {
  priv options : MemoryStoreOptions
  priv records : Array[StoreRecord]
  priv mut body_bytes : Int64
  priv mut logical_clock : Int64
  priv mut puts : Int64
  priv mut replacements : Int64
  priv mut evictions : Int64
  priv mut lookups : Int64
  priv mut hits : Int64
  priv mut misses : Int64
  priv mut invalidated_entries : Int64
  priv mut rejected_entries : Int64
}

///|
pub fn MemoryStore::new(options : MemoryStoreOptions) -> MemoryStore {
  MemoryStore::{
    options,
    records: [],
    body_bytes: 0,
    logical_clock: 0,
    puts: 0,
    replacements: 0,
    evictions: 0,
    lookups: 0,
    hits: 0,
    misses: 0,
    invalidated_entries: 0,
    rejected_entries: 0,
  }
}

///|
pub fn MemoryStore::default() -> MemoryStore {
  MemoryStore::new(MemoryStoreOptions::default())
}

///|
fn next_store_order(store : MemoryStore) -> Int64 {
  if store.logical_clock < MAX_DELTA_SECONDS {
    store.logical_clock = store.logical_clock + 1
  }
  store.logical_clock
}

///|
fn stored_connection_fields(headers : HeaderMap) -> Array[String] {
  let fields : Array[String] = []
  match headers.get("connection") {
    Some(value) =>
      for part in value.split(",") {
        let name = normalize_header_name(part.to_owned())
        if name != "" && !fields.contains(name) {
          fields.push(name)
        }
      }
    None => ()
  }
  fields
}

///|
fn is_hop_by_hop(name : String, connection_fields : Array[String]) -> Bool {
  name == "connection" ||
  name == "keep-alive" ||
  name == "proxy-authenticate" ||
  name == "proxy-authorization" ||
  name == "te" ||
  name == "trailer" ||
  name == "transfer-encoding" ||
  name == "upgrade" ||
  connection_fields.contains(name)
}

///|
fn copy_stored_response_headers(
  headers : HeaderMap,
  strip_set_cookie : Bool,
) -> HeaderMap {
  let result = HeaderMap::new()
  let connection_fields = stored_connection_fields(headers)
  for name in headers.names() {
    if !is_hop_by_hop(name, connection_fields) &&
      !(strip_set_cookie && name == "set-cookie") {
      replace_header_values(result, name, headers.get_all(name))
    }
  }
  result
}

///|
fn copy_stored_request_headers(
  headers : HeaderMap,
  vary : VarySpec,
  strip_credentials : Bool,
) -> HeaderMap {
  let result = HeaderMap::new()
  for name in headers.names() {
    let sensitive = name == "authorization" ||
      name == "proxy-authorization" ||
      name == "cookie"
    if !strip_credentials || !sensitive || vary.fields.contains(name) {
      replace_header_values(result, name, headers.get_all(name))
    }
  }
  result
}

///|
fn sanitize_stored_entry(
  entry : StoredEntry,
  options : MemoryStoreOptions,
) -> StoredEntry {
  let vary = parse_vary(entry.response.headers)
  StoredEntry::{
    ..entry,
    request: RequestMeta::{
      ..entry.request,
      headers: copy_stored_request_headers(
        entry.request.headers,
        vary,
        options.strip_request_credentials,
      ),
    },
    response: ResponseMeta::{
      ..entry.response,
      headers: copy_stored_response_headers(
        entry.response.headers,
        options.strip_set_cookie,
      ),
    },
  }
}

///|
fn MemoryStore::remove_record_at(
  self : MemoryStore,
  index : Int,
) -> StoreRecord {
  let removed = self.records.remove(index)
  self.body_bytes = self.body_bytes - removed.entry.body_size()
  removed
}

///|
fn MemoryStore::replacement_index(
  self : MemoryStore,
  key : PrimaryCacheKey,
  variant : VariantKey,
) -> Int? {
  for index = 0; index < self.records.length(); index = index + 1 {
    let entry = self.records[index].entry
    if entry.primary_key == key && entry.variant_key == variant {
      return Some(index)
    }
  }
  None
}

///|
fn MemoryStore::eviction_index(self : MemoryStore) -> Int {
  let mut selected = 0
  for index = 1; index < self.records.length(); index = index + 1 {
    let candidate = self.records[index]
    let current = self.records[selected]
    if candidate.access_order < current.access_order ||
      (
        candidate.access_order == current.access_order &&
        candidate.insertion_order < current.insertion_order
      ) {
      selected = index
    }
  }
  selected
}

///|
fn MemoryStore::evict_to_limits(self : MemoryStore) -> Unit {
  while self.records.length() > self.options.max_entries ||
        self.body_bytes > self.options.max_body_bytes {
    let index = self.eviction_index()
    ignore(self.remove_record_at(index))
    self.evictions = self.evictions + 1
  }
}

///|
pub fn MemoryStore::find_variants(
  self : MemoryStore,
  key : PrimaryCacheKey,
) -> Array[StoredEntry] {
  self.lookups = self.lookups + 1
  let order = next_store_order(self)
  let result : Array[StoredEntry] = []
  for record in self.records {
    if record.entry.primary_key == key {
      record.access_order = order
      result.push(record.entry.copy())
    }
  }
  if result.length() == 0 {
    self.misses = self.misses + 1
  } else {
    self.hits = self.hits + 1
  }
  result
}

///|
pub fn MemoryStore::put(
  self : MemoryStore,
  source_entry : StoredEntry,
) -> StorePutResult {
  if !source_entry.policy.cacheable ||
    source_entry.policy.no_store ||
    source_entry.policy.vary_star {
    self.rejected_entries = self.rejected_entries + 1
    return StoreRejectedNoStore
  }
  let size = source_entry.body_size()
  if size > self.options.max_body_size || size > self.options.max_body_bytes {
    self.rejected_entries = self.rejected_entries + 1
    return StoreRejectedOversized
  }
  if self.options.max_entries <= 0 || self.options.max_body_bytes <= 0 {
    self.rejected_entries = self.rejected_entries + 1
    return StoreRejectedCapacity
  }
  let entry = sanitize_stored_entry(source_entry.copy(), self.options)
  let mut replaced = false
  match self.replacement_index(entry.primary_key, entry.variant_key) {
    Some(index) => {
      ignore(self.remove_record_at(index))
      self.replacements = self.replacements + 1
      replaced = true
    }
    None => ()
  }
  let order = next_store_order(self)
  self.records.push(StoreRecord::{
    entry,
    access_order: order,
    insertion_order: order,
  })
  self.body_bytes = self.body_bytes + size
  self.puts = self.puts + 1
  self.evict_to_limits()
  if replaced {
    StoreReplacedResult
  } else {
    StoreInserted
  }
}

///|
pub fn MemoryStore::remove_variant(
  self : MemoryStore,
  key : PrimaryCacheKey,
  variant : VariantKey,
) -> Bool {
  match self.replacement_index(key, variant) {
    Some(index) => {
      ignore(self.remove_record_at(index))
      true
    }
    None => false
  }
}

///|
pub fn MemoryStore::invalidate_uri(self : MemoryStore, uri : String) -> Int {
  let target = normalize_cache_uri(uri).unwrap_or(uri.trim().to_owned())
  let mut removed = 0
  let mut index = self.records.length() - 1
  while index >= 0 && self.records.length() > 0 {
    if self.records[index].entry.primary_key.uri == target {
      ignore(self.remove_record_at(index))
      removed = removed + 1
    }
    index = index - 1
  }
  self.invalidated_entries = self.invalidated_entries + removed.to_int64()
  removed
}

///|
pub fn MemoryStore::clear(self : MemoryStore) -> Unit {
  self.records.clear()
  self.body_bytes = 0
}

///|
pub fn MemoryStore::stats(self : MemoryStore) -> StoreStats {
  StoreStats::{
    entries: self.records.length(),
    body_bytes: self.body_bytes,
    puts: self.puts,
    replacements: self.replacements,
    evictions: self.evictions,
    lookups: self.lookups,
    hits: self.hits,
    misses: self.misses,
    invalidated_entries: self.invalidated_entries,
    rejected_entries: self.rejected_entries,
  }
}

///|
pub impl CacheStore for MemoryStore with fn find_variants(self, key) {
  MemoryStore::find_variants(self, key)
}

///|
pub impl CacheStore for MemoryStore with fn put(self, entry) {
  MemoryStore::put(self, entry)
}

///|
pub impl CacheStore for MemoryStore with fn remove_variant(self, key, variant) {
  MemoryStore::remove_variant(self, key, variant)
}

///|
pub impl CacheStore for MemoryStore with fn invalidate_uri(self, uri) {
  MemoryStore::invalidate_uri(self, uri)
}

///|
pub impl CacheStore for MemoryStore with fn clear(self) {
  MemoryStore::clear(self)
}

///|
pub impl CacheStore for MemoryStore with fn stats(self) {
  MemoryStore::stats(self)
}
