///|
fn private_runtime_demo() -> Unit raise {
  let store = @mooncache.MemoryStore::default()
  let origin = @mooncache.FakeTransport::new([
    @support.response(
      200,
      [("Cache-Control", "private, max-age=60")],
      b"user profile",
      0L,
      0L,
    ),
  ])
  let runtime = @mooncache.CachedRuntime::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  let request = @mooncache.RuntimeRequest::get("https://example.test/profile")
  let first = runtime.execute(request, @mooncache.Timestamp::zero())
  let second = runtime.execute(request, @mooncache.Timestamp::from_seconds(1L))
  @support.print_result("private first", first)
  @support.print_result("private second", second)
  @support.require(second.source is CacheSource, "private cache may reuse")
  @support.require(origin.call_count() == 1, "private origin call count")
  @support.require(store.stats().entries == 1, "private response is stored")
}

///|
fn shared_runtime_demo() -> Unit raise {
  let store = @mooncache.MemoryStore::default()
  let origin = @mooncache.FakeTransport::new([
    @support.response(
      200,
      [("Cache-Control", "private, max-age=60")],
      b"user profile one",
      0L,
      0L,
    ),
    @support.response(
      200,
      [("Cache-Control", "private, max-age=60")],
      b"user profile two",
      1L,
      1L,
    ),
  ])
  let runtime = @mooncache.CachedRuntime::new(
    store,
    origin,
    @mooncache.CacheOptions::shared_cache(),
  )
  let request = @mooncache.RuntimeRequest::get("https://example.test/profile")
  let first = runtime.execute(request, @mooncache.Timestamp::zero())
  let second = runtime.execute(request, @mooncache.Timestamp::from_seconds(1L))
  @support.print_result("shared first", first)
  @support.print_result("shared second", second)
  @support.require(
    second.source is UpstreamSource,
    "shared cache must reject private response",
  )
  @support.require(origin.call_count() == 2, "shared origin call count")
  @support.require(store.stats().entries == 0, "shared store remains empty")
}

///|
fn main {
  println("shared_private")
  try! private_runtime_demo()
  try! shared_runtime_demo()
}
