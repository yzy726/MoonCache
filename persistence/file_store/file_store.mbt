///|
/// Errors raised by checked FileStore operations.
pub suberror FileStoreError {
  FileStoreIo(String)
  FileStoreCorrupt(String)
  FileStoreUnsupportedVersion(Int)
  FileStoreMetadataTooLarge(actual~ : Int, maximum~ : Int)
  FileStoreHeadersTooLarge(actual~ : Int, maximum~ : Int)
} derive(Eq, Debug)

///|
pub fn FileStoreError::message(self : FileStoreError) -> String {
  match self {
    FileStoreIo(message) => "file store I/O error: \{message}"
    FileStoreCorrupt(message) => "file store data is corrupt: \{message}"
    FileStoreUnsupportedVersion(version) =>
      "file store format version \{version} is not supported"
    FileStoreMetadataTooLarge(actual~, maximum~) =>
      "file store metadata size \{actual} exceeds \{maximum} bytes"
    FileStoreHeadersTooLarge(actual~, maximum~) =>
      "file store header size \{actual} exceeds \{maximum} bytes"
  }
}

///|
pub(all) struct FileStoreOptions {
  memory_options : @mooncache.MemoryStoreOptions
  max_metadata_bytes : Int
  max_header_bytes : Int
} derive(Eq, Debug)

///|
pub fn FileStoreOptions::default() -> FileStoreOptions {
  FileStoreOptions::{
    memory_options: @mooncache.MemoryStoreOptions::default(),
    max_metadata_bytes: 256 * 1024,
    max_header_bytes: 128 * 1024,
  }
}

///|
pub fn FileStoreOptions::with_memory_options(
  self : FileStoreOptions,
  memory_options : @mooncache.MemoryStoreOptions,
) -> FileStoreOptions {
  FileStoreOptions::{ ..self, memory_options, }
}

///|
pub fn FileStoreOptions::with_limits(
  max_entries : Int,
  max_body_bytes : Int64,
  max_body_size : Int64,
) -> FileStoreOptions {
  FileStoreOptions::default().with_memory_options(
    @mooncache.MemoryStoreOptions::with_limits(
      max_entries, max_body_bytes, max_body_size,
    ),
  )
}

///|
pub fn FileStoreOptions::with_metadata_limit(
  self : FileStoreOptions,
  maximum : Int,
) -> FileStoreOptions {
  FileStoreOptions::{
    ..self,
    max_metadata_bytes: if maximum < 0 {
      0
    } else {
      maximum
    },
  }
}

///|
pub fn FileStoreOptions::with_header_limit(
  self : FileStoreOptions,
  maximum : Int,
) -> FileStoreOptions {
  FileStoreOptions::{
    ..self,
    max_header_bytes: if maximum < 0 {
      0
    } else {
      maximum
    },
  }
}

///|
/// Summary of work performed while opening and recovering a durable store.
pub(all) struct FileStoreRecoveryReport {
  loaded_entries : Int
  quarantined_entries : Int
  dropped_entries : Int
  temp_files_removed : Int
  orphan_files_removed : Int
  indexes_rebuilt : Int
  manifest_rebuilt : Bool
} derive(Eq, Debug)

///|
fn FileStoreRecoveryReport::empty() -> FileStoreRecoveryReport {
  FileStoreRecoveryReport::{
    loaded_entries: 0,
    quarantined_entries: 0,
    dropped_entries: 0,
    temp_files_removed: 0,
    orphan_files_removed: 0,
    indexes_rebuilt: 0,
    manifest_rebuilt: false,
  }
}

///|
priv struct FileStorePaths {
  root : String
  index : String
  metadata : String
  bodies : String
  temp : String
  quarantine : String
  manifest : String
}

///|
fn join_store_path(parent : String, child : String) -> String {
  if parent.has_suffix("/") || parent.has_suffix("\\") {
    "\{parent}\{child}"
  } else {
    "\{parent}/\{child}"
  }
}

///|
fn FileStorePaths::new(root : String) -> FileStorePaths raise FileStoreError {
  guard root.trim() != "" && !root.contains("\u0000") else {
    raise FileStoreIo("cache root path is empty or contains NUL")
  }
  FileStorePaths::{
    root,
    index: join_store_path(root, "index"),
    metadata: join_store_path(root, "metadata"),
    bodies: join_store_path(root, "bodies"),
    temp: join_store_path(root, "temp"),
    quarantine: join_store_path(root, "quarantine"),
    manifest: join_store_path(root, "store.json"),
  }
}

///|
fn FileStorePaths::ensure_layout(
  self : FileStorePaths,
) -> Unit raise FileStoreError {
  native_mkdirs(self.root)
  native_mkdirs(self.index)
  native_mkdirs(self.metadata)
  native_mkdirs(self.bodies)
  native_mkdirs(self.temp)
  native_mkdirs(self.quarantine)
}

///|
fn metadata_filename(entry_id : String) -> String {
  "\{entry_id}.json"
}

///|
fn body_filename(digest : String) -> String {
  "\{digest}.body"
}

///|
fn index_filename(index_id : String) -> String {
  "\{index_id}.json"
}

///|
fn is_safe_child_name(name : String) -> Bool {
  name != "" &&
  name != "." &&
  name != ".." &&
  !name.contains("/") &&
  !name.contains("\\") &&
  !name.contains("\u0000")
}

///|
fn read_store_bytes(path : String) -> Bytes raise FileStoreError {
  @fs.read_file_to_bytes(path) catch {
    error => raise FileStoreIo("\{path}: \{error.to_repr().to_string()}")
  }
}

///|
fn read_store_text(path : String) -> String raise FileStoreError {
  @utf8.decode(read_store_bytes(path)) catch {
    _ => raise FileStoreCorrupt("persisted text is not valid UTF-8")
  }
}

///|
fn read_store_directory(path : String) -> Array[String] raise FileStoreError {
  @fs.read_dir(path) catch {
    error => raise FileStoreIo("\{path}: \{error.to_repr().to_string()}")
  }
}

///|
fn store_path_is_file(path : String) -> Bool raise FileStoreError {
  @fs.is_file(path) catch {
    error => raise FileStoreIo("\{path}: \{error.to_repr().to_string()}")
  }
}

///|
fn remove_store_file(path : String) -> Unit raise FileStoreError {
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      error => raise FileStoreIo("\{path}: \{error.to_repr().to_string()}")
    }
  }
}

///|
fn utf8_size(text : String) -> Int {
  native_text(text).length()
}

///|
fn write_text_if_changed(
  paths : FileStorePaths,
  path : String,
  prefix : String,
  text : String,
  maximum : Int,
) -> Unit raise FileStoreError {
  let encoded = native_text(text)
  guard encoded.length() <= maximum else {
    raise FileStoreMetadataTooLarge(actual=encoded.length(), maximum~)
  }
  let existing = if @fs.path_exists(path) {
    @fs.read_file_to_bytes(path) catch {
      _ => b""
    }
  } else {
    b""
  }
  if existing != encoded {
    native_atomic_write(path, paths.temp, prefix, encoded)
  }
}

///|
fn write_body_if_needed(
  paths : FileStorePaths,
  digest : String,
  body : Bytes,
) -> Unit raise FileStoreError {
  let path = join_store_path(paths.bodies, body_filename(digest))
  let valid_existing = if @fs.path_exists(path) {
    let existing = @fs.read_file_to_bytes(path) catch { _ => b"" }
    existing.length() == body.length() && body_file_digest(existing) == digest
  } else {
    false
  }
  if !valid_existing {
    native_atomic_write(path, paths.temp, digest, body)
  }
}

///|
fn cleanup_directory(
  directory : String,
  keep : Array[String],
) -> Int raise FileStoreError {
  let mut removed = 0
  for name in read_store_directory(directory) {
    if is_safe_child_name(name) && !keep.contains(name) {
      let path = join_store_path(directory, name)
      if store_path_is_file(path) {
        remove_store_file(path)
        removed = removed + 1
      }
    }
  }
  removed
}

///|
fn compare_string(left : String, right : String) -> Int {
  if left < right {
    -1
  } else if left > right {
    1
  } else {
    0
  }
}

///|
fn compare_entry_id(
  left : @mooncache.StoredEntry,
  right : @mooncache.StoredEntry,
) -> Int {
  compare_string(entry_file_id(left), entry_file_id(right))
}

///|
priv struct IndexAccumulator {
  index_id : String
  primary_key : @mooncache.PrimaryCacheKey
  entry_ids : Array[String]
}

///|
fn collect_indexes(
  entries : Array[@mooncache.StoredEntry],
) -> Array[IndexAccumulator] {
  let indexes : Array[IndexAccumulator] = []
  for entry in entries {
    let index_id = primary_index_id(entry.primary_key)
    let entry_id = entry_file_id(entry)
    let mut found = false
    for index in indexes {
      if index.index_id == index_id {
        index.entry_ids.push(entry_id)
        found = true
        break
      }
    }
    if !found {
      indexes.push(IndexAccumulator::{
        index_id,
        primary_key: entry.primary_key,
        entry_ids: [entry_id],
      })
    }
  }
  for index in indexes {
    index.entry_ids.sort_by(compare_string)
  }
  indexes.sort_by(fn(left, right) {
    compare_string(left.index_id, right.index_id)
  })
  indexes
}

///|
/// Native persistent implementation of the portable CacheStore contract.
///
/// A manifest is the atomic commit point. Bodies and entry metadata are
/// installed first; only ids listed by the last complete manifest are loaded
/// after a restart. Uncommitted files are therefore safe to garbage collect.
pub struct FileStore {
  priv paths : FileStorePaths
  priv options : FileStoreOptions
  priv mut memory : @mooncache.MemoryStore
  priv mut generation : Int64
  priv mut recovery : FileStoreRecoveryReport
  priv mut quarantine_serial : Int64
  priv mut last_error : String?
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
fn FileStore::snapshot_entries(
  self : FileStore,
) -> Array[@mooncache.StoredEntry] {
  let entries : Array[@mooncache.StoredEntry] = []
  for uri in self.memory.cached_uris() {
    for entry in self.memory.peek_variants(uri) {
      entries.push(entry)
    }
  }
  entries.sort_by(compare_entry_id)
  entries
}

///|
fn FileStore::restore_snapshot(
  self : FileStore,
  entries : Array[@mooncache.StoredEntry],
) -> Unit {
  self.memory = @mooncache.MemoryStore::new(self.options.memory_options)
  for entry in entries {
    ignore(self.memory.put(entry))
  }
}

///|
fn FileStore::quarantine_file(
  self : FileStore,
  source : String,
  original_name : String,
) -> Unit raise FileStoreError {
  self.quarantine_serial = self.quarantine_serial + 1
  let safe_name = if is_safe_child_name(original_name) {
    original_name
  } else {
    sha256_hex_text(original_name)
  }
  let destination = join_store_path(
    self.paths.quarantine,
    "\{safe_name}.\{self.quarantine_serial}.bad",
  )
  native_replace(source, destination)
}

///|
fn FileStore::persist_snapshot(self : FileStore) -> Int raise FileStoreError {
  let entries = self.snapshot_entries()
  let metadata_keep : Array[String] = []
  let body_keep : Array[String] = []
  let entry_ids : Array[String] = []
  for entry in entries {
    let entry_id = entry_file_id(entry)
    let digest = body_file_digest(entry.body)
    let metadata_name = metadata_filename(entry_id)
    let body_name = body_filename(digest)
    write_body_if_needed(self.paths, digest, entry.body)
    write_text_if_changed(
      self.paths,
      join_store_path(self.paths.metadata, metadata_name),
      entry_id,
      encode_entry_metadata(entry),
      self.options.max_metadata_bytes,
    )
    metadata_keep.push(metadata_name)
    if !body_keep.contains(body_name) {
      body_keep.push(body_name)
    }
    entry_ids.push(entry_id)
  }
  let index_keep : Array[String] = []
  for index in collect_indexes(entries) {
    let name = index_filename(index.index_id)
    let disk_index = DiskIndexV1::{
      format_version: FILE_STORE_FORMAT_VERSION,
      index_id: index.index_id,
      primary_method: index.primary_key.http_method,
      primary_uri: index.primary_key.uri,
      entry_ids: index.entry_ids,
    }
    write_text_if_changed(
      self.paths,
      join_store_path(self.paths.index, name),
      index.index_id,
      encode_index(disk_index),
      self.options.max_metadata_bytes,
    )
    index_keep.push(name)
  }
  let next_generation = if self.generation < @mooncache.MAX_DELTA_SECONDS {
    self.generation + 1
  } else {
    self.generation
  }
  let manifest = DiskManifestV1::{
    format_version: FILE_STORE_FORMAT_VERSION,
    generation: next_generation,
    entry_ids,
  }
  write_text_if_changed(
    self.paths,
    self.paths.manifest,
    "store",
    encode_manifest(manifest),
    self.options.max_metadata_bytes,
  )
  self.generation = next_generation
  let removed_metadata = cleanup_directory(self.paths.metadata, metadata_keep) catch {
    _ => 0
  }
  let removed_indexes = cleanup_directory(self.paths.index, index_keep) catch {
    _ => 0
  }
  let removed_bodies = cleanup_directory(self.paths.bodies, body_keep) catch {
    _ => 0
  }
  let removed_temp = cleanup_directory(self.paths.temp, []) catch { _ => 0 }
  removed_metadata + removed_indexes + removed_bodies + removed_temp
}

///|
fn manifest_ids_are_valid(ids : Array[String]) -> Bool {
  let seen : Array[String] = []
  for id in ids {
    if !is_lower_hex_digest(id) || seen.contains(id) {
      return false
    }
    seen.push(id)
  }
  true
}

///|
fn FileStore::load_manifest(
  self : FileStore,
) -> (DiskManifestV1?, Bool) raise FileStoreError {
  if !@fs.path_exists(self.paths.manifest) {
    return (None, true)
  }
  let mut result : DiskManifestV1? = None
  let mut rebuild = false
  try {
    let text = read_store_text(self.paths.manifest)
    guard utf8_size(text) <= self.options.max_metadata_bytes else {
      raise FileStoreCorrupt("store manifest exceeds configured size limit")
    }
    let manifest = decode_manifest(text)
    guard manifest.format_version == FILE_STORE_FORMAT_VERSION else {
      raise FileStoreUnsupportedVersion(manifest.format_version)
    }
    guard manifest.generation >= 0 && manifest_ids_are_valid(manifest.entry_ids) else {
      raise FileStoreCorrupt("store manifest contains invalid entry ids")
    }
    result = Some(manifest)
  } catch {
    FileStoreUnsupportedVersion(version) =>
      raise FileStoreUnsupportedVersion(version)
    FileStoreCorrupt(_) => {
      self.quarantine_file(self.paths.manifest, "store.json")
      rebuild = true
    }
    error => raise error
  }
  (result, rebuild)
}

///|
fn FileStore::scan_metadata_ids(
  self : FileStore,
) -> Array[String] raise FileStoreError {
  let ids : Array[String] = []
  for name in read_store_directory(self.paths.metadata) {
    if !is_safe_child_name(name) {
      continue
    }
    if name.has_suffix(".json") && name.length() == 69 {
      let id = name[:64].to_owned()
      if is_lower_hex_digest(id) {
        ids.push(id)
      } else {
        self.quarantine_file(join_store_path(self.paths.metadata, name), name)
      }
    } else {
      let path = join_store_path(self.paths.metadata, name)
      if store_path_is_file(path) {
        self.quarantine_file(path, name)
      }
    }
  }
  ids.sort_by(compare_string)
  ids
}

///|
fn FileStore::load_entry(
  self : FileStore,
  entry_id : String,
) -> @mooncache.StoredEntry raise FileStoreError {
  let metadata_path = join_store_path(
    self.paths.metadata,
    metadata_filename(entry_id),
  )
  guard @fs.path_exists(metadata_path) else {
    raise FileStoreCorrupt("manifest references missing metadata \{entry_id}")
  }
  let metadata_bytes = read_store_bytes(metadata_path)
  guard metadata_bytes.length() <= self.options.max_metadata_bytes else {
    raise FileStoreMetadataTooLarge(
      actual=metadata_bytes.length(),
      maximum=self.options.max_metadata_bytes,
    )
  }
  let metadata = decode_entry_metadata(
    @utf8.decode(metadata_bytes) catch {
      _ => raise FileStoreCorrupt("metadata is not valid UTF-8")
    },
  )
  guard metadata.entry_id == entry_id else {
    raise FileStoreCorrupt("metadata filename and entry id disagree")
  }
  guard is_lower_hex_digest(metadata.body_digest) else {
    raise FileStoreCorrupt("metadata contains an unsafe body id")
  }
  let body_path = join_store_path(
    self.paths.bodies,
    body_filename(metadata.body_digest),
  )
  guard @fs.path_exists(body_path) else {
    raise FileStoreCorrupt("metadata references a missing body")
  }
  let body = read_store_bytes(body_path)
  guard body.length().to_int64() <= self.options.memory_options.max_body_size &&
    body.length().to_int64() <= self.options.memory_options.max_body_bytes else {
    raise FileStoreCorrupt("persisted body exceeds configured capacity")
  }
  let header_size = persisted_header_bytes(metadata.request_headers) +
    persisted_header_bytes(metadata.response_headers)
  guard header_size <= self.options.max_header_bytes else {
    raise FileStoreHeadersTooLarge(
      actual=header_size,
      maximum=self.options.max_header_bytes,
    )
  }
  metadata.to_entry(body, self.options.max_header_bytes)
}

///|
fn equal_string_arrays(left : Array[String], right : Array[String]) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index = 0; index < left.length(); index = index + 1 {
    if left[index] != right[index] {
      return false
    }
  }
  true
}

///|
fn FileStore::index_is_current(
  self : FileStore,
  expected : IndexAccumulator,
) -> Bool raise FileStoreError {
  let name = index_filename(expected.index_id)
  let path = join_store_path(self.paths.index, name)
  if !@fs.path_exists(path) {
    return false
  }
  let valid = try {
    let text = read_store_text(path)
    guard utf8_size(text) <= self.options.max_metadata_bytes else {
      raise FileStoreMetadataTooLarge(
        actual=utf8_size(text),
        maximum=self.options.max_metadata_bytes,
      )
    }
    let index = decode_index(text)
    guard index.format_version == FILE_STORE_FORMAT_VERSION else {
      raise FileStoreUnsupportedVersion(index.format_version)
    }
    index.index_id == expected.index_id &&
    index.primary_method == expected.primary_key.http_method &&
    index.primary_uri == expected.primary_key.uri &&
    manifest_ids_are_valid(index.entry_ids) &&
    equal_string_arrays(index.entry_ids, expected.entry_ids)
  } catch {
    FileStoreCorrupt(_)
    | FileStoreUnsupportedVersion(_)
    | FileStoreMetadataTooLarge(_) => false
    error => raise error
  }
  if !valid {
    self.quarantine_file(path, name)
  }
  valid
}

///|
fn FileStore::recover(self : FileStore) -> Unit raise FileStoreError {
  let mut report = FileStoreRecoveryReport::empty()
  report = FileStoreRecoveryReport::{
    ..report,
    temp_files_removed: cleanup_directory(self.paths.temp, []),
  }
  let (manifest, rebuild_manifest) = self.load_manifest()
  report = FileStoreRecoveryReport::{
    ..report,
    manifest_rebuilt: rebuild_manifest,
  }
  let ids = match manifest {
    Some(value) => {
      self.generation = value.generation
      value.entry_ids
    }
    None => self.scan_metadata_ids()
  }
  let mut loaded = 0
  let mut quarantined = 0
  let mut dropped = 0
  for entry_id in ids {
    let metadata_path = join_store_path(
      self.paths.metadata,
      metadata_filename(entry_id),
    )
    let candidate : @mooncache.StoredEntry? = Some(self.load_entry(entry_id)) catch {
      FileStoreCorrupt(_)
      | FileStoreUnsupportedVersion(_)
      | FileStoreMetadataTooLarge(_)
      | FileStoreHeadersTooLarge(_) => {
        if @fs.path_exists(metadata_path) {
          self.quarantine_file(metadata_path, metadata_filename(entry_id))
          quarantined = quarantined + 1
        }
        dropped = dropped + 1
        None
      }
      error => raise error
    }
    match candidate {
      Some(entry) =>
        match self.memory.put(entry) {
          StoreInserted | StoreReplacedResult => loaded = loaded + 1
          _ => dropped = dropped + 1
        }
      None => ()
    }
  }
  let mut rebuilt_indexes = 0
  for expected in collect_indexes(self.snapshot_entries()) {
    if !self.index_is_current(expected) {
      rebuilt_indexes = rebuilt_indexes + 1
    }
  }
  let orphans = self.persist_snapshot()
  self.recovery = FileStoreRecoveryReport::{
    loaded_entries: loaded,
    quarantined_entries: quarantined,
    dropped_entries: dropped,
    temp_files_removed: report.temp_files_removed,
    orphan_files_removed: orphans,
    indexes_rebuilt: rebuilt_indexes,
    manifest_rebuilt: report.manifest_rebuilt,
  }
}

///|
pub fn FileStore::open(
  root : String,
  options? : FileStoreOptions = FileStoreOptions::default(),
) -> FileStore raise FileStoreError {
  let paths = FileStorePaths::new(root)
  paths.ensure_layout()
  let store = FileStore::{
    paths,
    options,
    memory: @mooncache.MemoryStore::new(options.memory_options),
    generation: 0,
    recovery: FileStoreRecoveryReport::empty(),
    quarantine_serial: 0,
    last_error: None,
    puts: 0,
    replacements: 0,
    evictions: 0,
    lookups: 0,
    hits: 0,
    misses: 0,
    invalidated_entries: 0,
    rejected_entries: 0,
  }
  store.recover()
  store
}

///|
pub fn FileStore::root(self : FileStore) -> String {
  self.paths.root
}

///|
pub fn FileStore::options(self : FileStore) -> FileStoreOptions {
  self.options
}

///|
pub fn FileStore::recovery_report(self : FileStore) -> FileStoreRecoveryReport {
  self.recovery
}

///|
pub fn FileStore::last_error(self : FileStore) -> String? {
  self.last_error
}

///|
pub fn FileStore::cached_uris(self : FileStore) -> Array[String] {
  self.memory.cached_uris()
}

///|
pub fn FileStore::peek_variants(
  self : FileStore,
  uri : String,
) -> Array[@mooncache.StoredEntry] {
  self.memory.peek_variants(uri)
}

///|
pub fn FileStore::variant_count(self : FileStore, uri : String) -> Int {
  self.memory.variant_count(uri)
}

///|
pub fn FileStore::find_variants(
  self : FileStore,
  key : @mooncache.PrimaryCacheKey,
) -> Array[@mooncache.StoredEntry] {
  self.lookups = self.lookups + 1
  let result = self.memory.find_variants(key)
  if result.length() == 0 {
    self.misses = self.misses + 1
  } else {
    self.hits = self.hits + 1
  }
  result
}

///|
pub fn FileStore::put_checked(
  self : FileStore,
  entry : @mooncache.StoredEntry,
) -> @mooncache.StorePutResult raise FileStoreError {
  let before = self.snapshot_entries()
  let before_count = before.length()
  let result = self.memory.put(entry)
  match result {
    StoreRejectedNoStore | StoreRejectedOversized | StoreRejectedCapacity => {
      self.rejected_entries = self.rejected_entries + 1
      return result
    }
    _ => ()
  }
  ignore(self.persist_snapshot()) catch {
    error => {
      self.restore_snapshot(before)
      self.rejected_entries = self.rejected_entries + 1
      self.last_error = Some(error.message())
      raise error
    }
  }
  let after_count = self.memory.stats().entries
  let evicted = match result {
    StoreInserted =>
      if before_count + 1 > after_count {
        before_count + 1 - after_count
      } else {
        0
      }
    StoreReplacedResult =>
      if before_count > after_count {
        before_count - after_count
      } else {
        0
      }
    _ => 0
  }
  self.puts = self.puts + 1
  self.evictions = self.evictions + evicted.to_int64()
  if result is StoreReplacedResult {
    self.replacements = self.replacements + 1
  }
  self.last_error = None
  result
}

///|
pub fn FileStore::put(
  self : FileStore,
  entry : @mooncache.StoredEntry,
) -> @mooncache.StorePutResult {
  self.put_checked(entry) catch {
    _ => StoreRejectedCapacity
  }
}

///|
pub fn FileStore::remove_variant_checked(
  self : FileStore,
  key : @mooncache.PrimaryCacheKey,
  variant : @mooncache.VariantKey,
) -> Bool raise FileStoreError {
  let before = self.snapshot_entries()
  if !self.memory.remove_variant(key, variant) {
    return false
  }
  ignore(self.persist_snapshot()) catch {
    error => {
      self.restore_snapshot(before)
      self.last_error = Some(error.message())
      raise error
    }
  }
  self.last_error = None
  true
}

///|
pub fn FileStore::remove_variant(
  self : FileStore,
  key : @mooncache.PrimaryCacheKey,
  variant : @mooncache.VariantKey,
) -> Bool {
  self.remove_variant_checked(key, variant) catch {
    _ => false
  }
}

///|
pub fn FileStore::invalidate_uri_checked(
  self : FileStore,
  uri : String,
) -> Int raise FileStoreError {
  let before = self.snapshot_entries()
  let removed = self.memory.invalidate_uri(uri)
  if removed == 0 {
    return 0
  }
  ignore(self.persist_snapshot()) catch {
    error => {
      self.restore_snapshot(before)
      self.last_error = Some(error.message())
      raise error
    }
  }
  self.invalidated_entries = self.invalidated_entries + removed.to_int64()
  self.last_error = None
  removed
}

///|
pub fn FileStore::invalidate_uri(self : FileStore, uri : String) -> Int {
  self.invalidate_uri_checked(uri) catch {
    _ => 0
  }
}

///|
pub fn FileStore::clear_checked(self : FileStore) -> Unit raise FileStoreError {
  let before = self.snapshot_entries()
  self.memory.clear()
  ignore(self.persist_snapshot()) catch {
    error => {
      self.restore_snapshot(before)
      self.last_error = Some(error.message())
      raise error
    }
  }
  ignore(cleanup_directory(self.paths.quarantine, []))
  self.last_error = None
}

///|
pub fn FileStore::clear(self : FileStore) -> Unit {
  self.clear_checked() catch {
    _ => ()
  }
}

///|
/// Rewrite indexes and the manifest, then remove unreferenced bodies,
/// metadata, indexes, and abandoned temporary files.
pub fn FileStore::compact(self : FileStore) -> Int raise FileStoreError {
  let removed = self.persist_snapshot()
  self.last_error = None
  removed
}

///|
pub fn FileStore::purge_quarantine(
  self : FileStore,
) -> Int raise FileStoreError {
  cleanup_directory(self.paths.quarantine, [])
}

///|
pub fn FileStore::stats(self : FileStore) -> @mooncache.StoreStats {
  let current = self.memory.stats()
  @mooncache.StoreStats::{
    entries: current.entries,
    body_bytes: current.body_bytes,
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
pub impl @mooncache.CacheStore for FileStore with fn find_variants(self, key) {
  FileStore::find_variants(self, key)
}

///|
pub impl @mooncache.CacheStore for FileStore with fn put(self, entry) {
  FileStore::put(self, entry)
}

///|
pub impl @mooncache.CacheStore for FileStore with fn remove_variant(
  self,
  key,
  variant,
) {
  FileStore::remove_variant(self, key, variant)
}

///|
pub impl @mooncache.CacheStore for FileStore with fn invalidate_uri(self, uri) {
  FileStore::invalidate_uri(self, uri)
}

///|
pub impl @mooncache.CacheStore for FileStore with fn clear(self) {
  FileStore::clear(self)
}

///|
pub impl @mooncache.CacheStore for FileStore with fn stats(self) {
  FileStore::stats(self)
}
