///|
test "memory store put then find" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry([], [("Cache-Control", "max-age=60")], b"body", 1)
  assert_true(store.put(entry) is StoreInserted)
  let found = store.find_variants(entry.primary_key)
  assert_eq(found.length(), 1)
  assert_eq(found[0].body, b"body")
}

///|
test "memory store retains multiple variants" {
  let store = @MoonCache.MemoryStore::default()
  let english = policy_entry(
    [("Accept-Language", "en")],
    [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
    b"en",
    1,
  )
  let chinese = policy_entry(
    [("Accept-Language", "zh")],
    [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
    b"zh",
    2,
  )
  assert_true(store.put(english) is StoreInserted)
  assert_true(store.put(chinese) is StoreInserted)
  assert_eq(store.find_variants(english.primary_key).length(), 2)
}

///|
test "memory store replaces equal variant" {
  let store = @MoonCache.MemoryStore::default()
  let old = policy_entry([], [("Cache-Control", "max-age=60")], b"old", 1)
  let new = policy_entry([], [("Cache-Control", "max-age=120")], b"new", 2)
  ignore(store.put(old))
  assert_true(store.put(new) is StoreReplacedResult)
  let found = store.find_variants(new.primary_key)
  assert_eq(found.length(), 1)
  assert_eq(found[0].body, b"new")
  assert_eq(store.stats().replacements, 1)
}

///|
test "memory store evicts least recently used entry count" {
  let store = @MoonCache.MemoryStore::new(
    @MoonCache.MemoryStoreOptions::with_limits(2, 1_000, 1_000),
  )
  let first = policy_entry_for_uri(
    "https://example.test/first",
    [],
    [("Cache-Control", "max-age=60")],
    b"1",
    1,
  )
  let second = policy_entry_for_uri(
    "https://example.test/second",
    [],
    [("Cache-Control", "max-age=60")],
    b"2",
    2,
  )
  let third = policy_entry_for_uri(
    "https://example.test/third",
    [],
    [("Cache-Control", "max-age=60")],
    b"3",
    3,
  )
  ignore(store.put(first))
  ignore(store.put(second))
  ignore(store.find_variants(first.primary_key))
  ignore(store.put(third))
  assert_eq(store.find_variants(first.primary_key).length(), 1)
  assert_eq(store.find_variants(second.primary_key).length(), 0)
  assert_eq(store.find_variants(third.primary_key).length(), 1)
  assert_eq(store.stats().evictions, 1)
}

///|
test "memory store evicts to total body byte limit" {
  let store = @MoonCache.MemoryStore::new(
    @MoonCache.MemoryStoreOptions::with_limits(10, 5, 5),
  )
  let first = policy_entry_for_uri(
    "https://example.test/first",
    [],
    [("Cache-Control", "max-age=60")],
    b"123",
    1,
  )
  let second = policy_entry_for_uri(
    "https://example.test/second",
    [],
    [("Cache-Control", "max-age=60")],
    b"456",
    2,
  )
  ignore(store.put(first))
  ignore(store.put(second))
  assert_eq(store.stats().entries, 1)
  assert_eq(store.stats().body_bytes, 3)
}

///|
test "memory store rejects oversized body" {
  let store = @MoonCache.MemoryStore::new(
    @MoonCache.MemoryStoreOptions::with_limits(10, 100, 3),
  )
  let entry = policy_entry([], [("Cache-Control", "max-age=60")], b"1234", 1)
  assert_true(store.put(entry) is StoreRejectedOversized)
  assert_eq(store.stats().entries, 0)
}

///|
test "memory store rejects no-store entry" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry([], [("Cache-Control", "no-store")], b"body", 1)
  assert_true(store.put(entry) is StoreRejectedNoStore)
  assert_eq(store.stats().rejected_entries, 1)
}

///|
test "memory store rejects disabled capacity" {
  let store = @MoonCache.MemoryStore::new(
    @MoonCache.MemoryStoreOptions::with_limits(0, 100, 100),
  )
  let entry = policy_entry([], [("Cache-Control", "max-age=60")], b"body", 1)
  assert_true(store.put(entry) is StoreRejectedCapacity)
}

///|
test "memory store invalidates all URI variants" {
  let store = @MoonCache.MemoryStore::default()
  let english = policy_entry(
    [("Accept-Language", "en")],
    [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
    b"en",
    1,
  )
  let chinese = policy_entry(
    [("Accept-Language", "zh")],
    [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
    b"zh",
    2,
  )
  ignore(store.put(english))
  ignore(store.put(chinese))
  assert_eq(store.invalidate_uri("HTTPS://EXAMPLE.TEST:443/data"), 2)
  assert_eq(store.stats().entries, 0)
  assert_eq(store.stats().invalidated_entries, 2)
}

///|
test "memory store removes one variant" {
  let store = @MoonCache.MemoryStore::default()
  let english = policy_entry(
    [("Accept-Language", "en")],
    [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
    b"en",
    1,
  )
  let chinese = policy_entry(
    [("Accept-Language", "zh")],
    [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
    b"zh",
    2,
  )
  ignore(store.put(english))
  ignore(store.put(chinese))
  assert_true(store.remove_variant(english.primary_key, english.variant_key))
  assert_eq(store.find_variants(english.primary_key).length(), 1)
}

///|
test "memory store clear resets current capacity" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry([], [("Cache-Control", "max-age=60")], b"body", 1)
  ignore(store.put(entry))
  store.clear()
  assert_eq(store.stats().entries, 0)
  assert_eq(store.stats().body_bytes, 0)
}

///|
test "memory store lookup statistics distinguish hit and miss" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry([], [("Cache-Control", "max-age=60")], b"body", 1)
  ignore(store.put(entry))
  ignore(store.find_variants(entry.primary_key))
  ignore(
    store.find_variants(
      @MoonCache.PrimaryCacheKey::new("GET", "https://example.test/missing"),
    ),
  )
  let stats = @MoonCache.CacheStore::stats(store)
  assert_eq(stats.lookups, 2)
  assert_eq(stats.hits, 1)
  assert_eq(stats.misses, 1)
}

///|
test "memory store strips non-Vary request credentials" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry(
    [
      ("Authorization", "Bearer secret"),
      ("Cookie", "session=secret"),
      ("Accept", "application/json"),
    ],
    [("Cache-Control", "private, max-age=60")],
    b"body",
    1,
  )
  ignore(store.put(entry))
  let found = store.find_variants(entry.primary_key)[0]
  assert_false(found.request.headers.contains("authorization"))
  assert_false(found.request.headers.contains("cookie"))
  assert_true(found.request.headers.contains("accept"))
}

///|
test "memory store retains credential field named by Vary" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry(
    [("Cookie", "theme=dark")],
    [("Cache-Control", "private, max-age=60"), ("Vary", "Cookie")],
    b"body",
    1,
  )
  ignore(store.put(entry))
  let found = store.find_variants(entry.primary_key)[0]
  assert_eq(found.request.headers.get("cookie"), Some("theme=dark"))
}

///|
test "memory store strips Set-Cookie and hop-by-hop response fields" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry(
    [],
    [
      ("Cache-Control", "max-age=60"),
      ("Set-Cookie", "session=secret"),
      ("Connection", "X-Hop"),
      ("X-Hop", "secret"),
      ("Transfer-Encoding", "chunked"),
    ],
    b"body",
    1,
  )
  ignore(store.put(entry))
  let found = store.find_variants(entry.primary_key)[0]
  assert_false(found.response.headers.contains("set-cookie"))
  assert_false(found.response.headers.contains("connection"))
  assert_false(found.response.headers.contains("x-hop"))
  assert_false(found.response.headers.contains("transfer-encoding"))
}

///|
test "memory store returns defensive metadata copies" {
  let store = @MoonCache.MemoryStore::default()
  let entry = policy_entry(
    [],
    [("Cache-Control", "max-age=60"), ("ETag", "\"v1\"")],
    b"body",
    1,
  )
  ignore(store.put(entry))
  let first = store.find_variants(entry.primary_key)[0]
  ignore(first.response.headers.set("etag", "\"mutated\""))
  let second = store.find_variants(entry.primary_key)[0]
  assert_eq(second.response.headers.get("etag"), Some("\"v1\""))
}
