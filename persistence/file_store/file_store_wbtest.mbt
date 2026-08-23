///|
fn test_store_path(root : String, child : String) -> String {
  "\{root}/\{child}"
}

///|
fn remove_test_file(path : String) -> Unit {
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
fn remove_test_directory(path : String) -> Unit {
  if !@fs.path_exists(path) {
    return
  }
  let names : Array[String] = @fs.read_dir(path) catch { _ => [] }
  for name in names {
    let child = test_store_path(path, name)
    let is_file = @fs.is_file(child) catch { _ => false }
    if is_file {
      remove_test_file(child)
    }
  }
  @fs.remove_dir(path) catch {
    _ => ()
  }
}

///|
fn reset_test_store(root : String) -> Unit {
  for child in ["index", "metadata", "bodies", "temp", "quarantine"] {
    remove_test_directory(test_store_path(root, child))
  }
  remove_test_file(test_store_path(root, "store.json"))
  remove_test_directory(root)
}

///|
fn test_headers(pairs : Array[(String, String)]) -> @mooncache.HeaderMap {
  let headers = @mooncache.HeaderMap::new()
  for pair in pairs {
    ignore(headers.append(pair.0, pair.1))
  }
  headers
}

///|
fn durable_test_entry(
  uri : String,
  request_headers : Array[(String, String)],
  response_headers : Array[(String, String)],
  body : Bytes,
  tick : Int64,
) -> @mooncache.StoredEntry {
  let request = @mooncache.RequestMeta::new(
    "GET",
    uri,
    test_headers(request_headers),
    @mooncache.Timestamp::from_seconds(tick),
  )
  let response = @mooncache.ResponseMeta::complete(
    200,
    test_headers(response_headers),
    @mooncache.Timestamp::from_seconds(tick),
    @mooncache.Timestamp::from_seconds(tick),
  )
  let primary = @mooncache.PrimaryCacheKey::from_request(request).unwrap()
  let variant = @mooncache.build_variant_key(
    request.headers,
    @mooncache.parse_vary(response.headers),
  ).unwrap()
  @mooncache.StoredEntry::new(
    primary,
    variant,
    request,
    response,
    body,
    @mooncache.StoredPolicy::cacheable(
      @mooncache.DeltaSeconds::from_seconds(60),
      false,
    ),
    @mooncache.Timestamp::from_seconds(tick),
  )
}

///|
fn default_durable_entry(
  uri : String,
  body : Bytes,
  tick : Int64,
) -> @mooncache.StoredEntry {
  durable_test_entry(uri, [], [("Cache-Control", "max-age=60")], body, tick)
}

///|
test "file store persists metadata and body across reopen" {
  let root = "target/mooncache_file_store_tests/reopen"
  reset_test_store(root)
  let entry = durable_test_entry(
    "https://example.test/data",
    [("Accept", "application/json")],
    [("Cache-Control", "max-age=60"), ("Content-Type", "application/json")],
    b"{\"ok\":true}",
    10,
  )
  let store = FileStore::open(root)
  assert_true(store.put_checked(entry) is @mooncache.StoreInserted)
  let entry_id = entry_file_id(entry)
  let digest = body_file_digest(entry.body)
  assert_true(
    @fs.path_exists(test_store_path(root, "metadata/\{entry_id}.json")),
  )
  assert_true(@fs.path_exists(test_store_path(root, "bodies/\{digest}.body")))
  let reopened = FileStore::open(root)
  let found = reopened.find_variants(entry.primary_key)
  assert_eq(found.length(), 1)
  assert_eq(found[0].body, entry.body)
  assert_eq(
    found[0].response.headers.get("content-type"),
    Some("application/json"),
  )
  assert_eq(reopened.recovery_report().loaded_entries, 1)
  reset_test_store(root)
}

///|
test "file store retains Vary variants and replaces one variant" {
  let root = "target/mooncache_file_store_tests/variants"
  reset_test_store(root)
  let response_headers = [
    ("Cache-Control", "max-age=60"),
    ("Vary", "Accept-Language"),
  ]
  let english_old = durable_test_entry(
    "https://example.test/greeting",
    [("Accept-Language", "en")],
    response_headers,
    b"hello-old",
    1,
  )
  let chinese = durable_test_entry(
    "https://example.test/greeting",
    [("Accept-Language", "zh")],
    response_headers,
    b"nihao",
    2,
  )
  let english_new = durable_test_entry(
    "https://example.test/greeting",
    [("Accept-Language", "en")],
    response_headers,
    b"hello-new",
    3,
  )
  let store = FileStore::open(root)
  assert_true(store.put_checked(english_old) is @mooncache.StoreInserted)
  assert_true(store.put_checked(chinese) is @mooncache.StoreInserted)
  assert_true(store.put_checked(english_new) is @mooncache.StoreReplacedResult)
  assert_eq(store.stats().replacements, 1)
  let reopened = FileStore::open(root)
  let found = reopened.find_variants(english_new.primary_key)
  assert_eq(found.length(), 2)
  let mut saw_english = false
  let mut saw_chinese = false
  for entry in found {
    if entry.body == b"hello-new" {
      saw_english = true
    }
    if entry.body == b"nihao" {
      saw_chinese = true
    }
    assert_false(entry.body == b"hello-old")
  }
  assert_true(saw_english)
  assert_true(saw_chinese)
  reset_test_store(root)
}

///|
test "file store persists deterministic capacity eviction" {
  let root = "target/mooncache_file_store_tests/eviction"
  reset_test_store(root)
  let options = FileStoreOptions::with_limits(1, 32, 32)
  let first = default_durable_entry("https://example.test/first", b"first", 1)
  let second = default_durable_entry(
    "https://example.test/second", b"second", 2,
  )
  let store = FileStore::open(root, options~)
  ignore(store.put_checked(first))
  ignore(store.put_checked(second))
  assert_eq(store.stats().entries, 1)
  assert_eq(store.stats().evictions, 1)
  let reopened = FileStore::open(root, options~)
  assert_eq(reopened.find_variants(first.primary_key).length(), 0)
  assert_eq(reopened.find_variants(second.primary_key).length(), 1)
  reset_test_store(root)
}

///|
test "file store rejects no-store and oversized entries" {
  let root = "target/mooncache_file_store_tests/rejections"
  reset_test_store(root)
  let store = FileStore::open(
    root,
    options=FileStoreOptions::with_limits(4, 16, 3),
  )
  let oversized = default_durable_entry(
    "https://example.test/large", b"1234", 1,
  )
  let ordinary = default_durable_entry("https://example.test/private", b"ok", 2)
  let no_store = @mooncache.StoredEntry::{
    ..ordinary,
    policy: @mooncache.StoredPolicy::uncacheable(),
  }
  assert_true(store.put_checked(oversized) is @mooncache.StoreRejectedOversized)
  assert_true(store.put_checked(no_store) is @mooncache.StoreRejectedNoStore)
  assert_eq(store.stats().entries, 0)
  assert_eq(store.stats().rejected_entries, 2)
  reset_test_store(root)
}

///|
test "file store remove invalidate clear and compact survive reopen" {
  let root = "target/mooncache_file_store_tests/mutations"
  reset_test_store(root)
  let vary_headers = [
    ("Cache-Control", "max-age=60"),
    ("Vary", "Accept-Language"),
  ]
  let english = durable_test_entry(
    "https://example.test/data",
    [("Accept-Language", "en")],
    vary_headers,
    b"en",
    1,
  )
  let chinese = durable_test_entry(
    "https://example.test/data",
    [("Accept-Language", "zh")],
    vary_headers,
    b"zh",
    2,
  )
  let other = default_durable_entry("https://example.test/other", b"other", 3)
  let store = FileStore::open(root)
  ignore(store.put_checked(english))
  ignore(store.put_checked(chinese))
  ignore(store.put_checked(other))
  assert_true(
    store.remove_variant_checked(english.primary_key, english.variant_key),
  )
  assert_eq(store.invalidate_uri_checked(chinese.request.uri), 1)
  assert_eq(store.compact(), 0)
  let reopened = FileStore::open(root)
  assert_eq(reopened.variant_count(chinese.request.uri), 0)
  assert_eq(reopened.variant_count(other.request.uri), 1)
  reopened.clear_checked()
  assert_eq(FileStore::open(root).stats().entries, 0)
  reset_test_store(root)
}

///|
test "file store removes abandoned temporary and orphan files on recovery" {
  let root = "target/mooncache_file_store_tests/orphans"
  reset_test_store(root)
  ignore(FileStore::open(root))
  let abandoned = test_store_path(root, "temp/abandoned.tmp")
  let orphan_body = test_store_path(root, "bodies/orphan.body")
  @fs.write_string_to_file(abandoned, "partial")
  @fs.write_string_to_file(orphan_body, "orphan")
  let reopened = FileStore::open(root)
  let report = reopened.recovery_report()
  assert_eq(report.temp_files_removed, 1)
  assert_true(report.orphan_files_removed >= 1)
  assert_false(@fs.path_exists(abandoned))
  assert_false(@fs.path_exists(orphan_body))
  reset_test_store(root)
}

///|
test "file store rebuilds a corrupt manifest by scanning metadata" {
  let root = "target/mooncache_file_store_tests/manifest_recovery"
  reset_test_store(root)
  let entry = default_durable_entry(
    "https://example.test/recover", b"recoverable", 1,
  )
  let store = FileStore::open(root)
  ignore(store.put_checked(entry))
  @fs.write_string_to_file(test_store_path(root, "store.json"), "{broken")
  let reopened = FileStore::open(root)
  assert_eq(reopened.find_variants(entry.primary_key).length(), 1)
  assert_true(reopened.recovery_report().manifest_rebuilt)
  assert_eq(reopened.recovery_report().loaded_entries, 1)
  assert_true(@fs.read_dir(test_store_path(root, "quarantine")).length() >= 1)
  reset_test_store(root)
}

///|
test "file store quarantines corrupt metadata and drops its entry" {
  let root = "target/mooncache_file_store_tests/metadata_corruption"
  reset_test_store(root)
  let entry = default_durable_entry(
    "https://example.test/corrupt-metadata", b"body", 1,
  )
  let store = FileStore::open(root)
  ignore(store.put_checked(entry))
  let metadata = test_store_path(root, "metadata/\{entry_file_id(entry)}.json")
  @fs.write_string_to_file(metadata, "not-json")
  let reopened = FileStore::open(root)
  let report = reopened.recovery_report()
  assert_eq(reopened.stats().entries, 0)
  assert_eq(report.quarantined_entries, 1)
  assert_eq(report.dropped_entries, 1)
  assert_false(@fs.path_exists(metadata))
  reset_test_store(root)
}

///|
test "file store detects a body digest mismatch during recovery" {
  let root = "target/mooncache_file_store_tests/body_corruption"
  reset_test_store(root)
  let entry = default_durable_entry(
    "https://example.test/corrupt-body", b"expected", 1,
  )
  let store = FileStore::open(root)
  ignore(store.put_checked(entry))
  let body_path = test_store_path(
    root,
    "bodies/\{body_file_digest(entry.body)}.body",
  )
  @fs.write_bytes_to_file(body_path, b"tampered")
  let reopened = FileStore::open(root)
  assert_eq(reopened.stats().entries, 0)
  assert_eq(reopened.recovery_report().quarantined_entries, 1)
  assert_eq(reopened.recovery_report().dropped_entries, 1)
  reset_test_store(root)
}

///|
test "file store rebuilds missing and corrupt indexes" {
  let root = "target/mooncache_file_store_tests/index_recovery"
  reset_test_store(root)
  let entry = default_durable_entry(
    "https://example.test/indexed", b"indexed", 1,
  )
  let store = FileStore::open(root)
  ignore(store.put_checked(entry))
  let index_id = primary_index_id(entry.primary_key)
  let index_path = test_store_path(root, "index/\{index_id}.json")
  remove_test_file(index_path)
  let missing_recovery = FileStore::open(root)
  assert_eq(missing_recovery.recovery_report().indexes_rebuilt, 1)
  assert_true(@fs.path_exists(index_path))
  @fs.write_string_to_file(index_path, "{corrupt")
  let corrupt_recovery = FileStore::open(root)
  assert_eq(corrupt_recovery.recovery_report().indexes_rebuilt, 1)
  assert_eq(corrupt_recovery.find_variants(entry.primary_key).length(), 1)
  reset_test_store(root)
}

///|
test "file store refuses an unknown manifest version" {
  let root = "target/mooncache_file_store_tests/version"
  reset_test_store(root)
  ignore(FileStore::open(root))
  @fs.write_string_to_file(
    test_store_path(root, "store.json"),
    "{\"format_version\":9,\"generation\":\"0\",\"entry_ids\":[]}",
  )
  let mut rejected = false
  try ignore(FileStore::open(root)) catch {
    FileStoreUnsupportedVersion(9) => rejected = true
    error => raise error
  } noraise {
    _ => ()
  }
  assert_true(rejected)
  reset_test_store(root)
}

///|
test "file store uses digest-only filenames for hostile-looking URIs" {
  let root = "target/mooncache_file_store_tests/path_safety"
  reset_test_store(root)
  let entry = default_durable_entry(
    "https://example.test/../../secret?name=..\\token", b"safe", 1,
  )
  let store = FileStore::open(root)
  ignore(store.put_checked(entry))
  let entry_id = entry_file_id(entry)
  assert_true(is_lower_hex_digest(entry_id))
  let metadata_names = @fs.read_dir(test_store_path(root, "metadata"))
  assert_eq(metadata_names, ["\{entry_id}.json"])
  assert_false(metadata_names[0].contains("secret"))
  reset_test_store(root)
}

///|
test "file store validates its root and persisted header limit" {
  let mut invalid_root_rejected = false
  try ignore(FileStore::open("")) catch {
    FileStoreIo(_) => invalid_root_rejected = true
    error => raise error
  } noraise {
    _ => ()
  }
  assert_true(invalid_root_rejected)

  let root = "target/mooncache_file_store_tests/header_limit"
  reset_test_store(root)
  let entry = durable_test_entry(
    "https://example.test/header-limit",
    [("X-Large", "1234567890")],
    [("Cache-Control", "max-age=60")],
    b"body",
    1,
  )
  ignore(FileStore::open(root).put_checked(entry))
  let strict = FileStoreOptions::default().with_header_limit(8)
  let reopened = FileStore::open(root, options=strict)
  assert_eq(reopened.stats().entries, 0)
  assert_eq(reopened.recovery_report().quarantined_entries, 1)
  reset_test_store(root)
}
