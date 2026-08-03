///|
fn run() -> Unit raise {
  let store = @mooncache.MemoryStore::default()
  let origin = @mooncache.FakeTransport::new([
    @support.response(
      200,
      [("Cache-Control", "max-age=60")],
      b"hello from origin",
      0L,
      0L,
    ),
  ])
  let runtime = @mooncache.CachedRuntime::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  let request = @mooncache.RuntimeRequest::get("https://example.test/greeting")
  let first = runtime.execute(request, @mooncache.Timestamp::zero())
  let second = runtime.execute(request, @mooncache.Timestamp::from_seconds(10L))
  println("basic_cache")
  @support.print_result("first", first)
  @support.print_result("second", second)
  println("origin calls: \{origin.call_count()}")
  @support.require(first.source is UpstreamSource, "first request must miss")
  @support.require(second.source is CacheSource, "second request must hit")
  @support.require(second.body == b"hello from origin", "body must be reused")
  @support.require(origin.call_count() == 1, "origin must be called once")
}

///|
fn main {
  try! run()
}
