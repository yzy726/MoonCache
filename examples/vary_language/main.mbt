///|
fn run() -> Unit raise {
  let store = @mooncache.MemoryStore::default()
  let origin = @mooncache.FakeTransport::new([
    @support.response(
      200,
      [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
      b"Hello",
      0L,
      0L,
    ),
    @support.response(
      200,
      [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
      b"Ni hao",
      1L,
      1L,
    ),
  ])
  let runtime = @mooncache.CachedRuntime::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  let uri = "https://example.test/greeting"
  let english = @support.request("GET", uri, [("Accept-Language", "en")])
  let chinese = @support.request("GET", uri, [("Accept-Language", "zh-CN")])
  let en_first = runtime.execute(english, @mooncache.Timestamp::zero())
  let zh_first = runtime.execute(
    chinese,
    @mooncache.Timestamp::from_seconds(1L),
  )
  let en_again = runtime.execute(
    english,
    @mooncache.Timestamp::from_seconds(2L),
  )
  println("vary_language")
  @support.print_result("en first", en_first)
  @support.print_result("zh first", zh_first)
  @support.print_result("en again", en_again)
  println("stored variants: \{store.stats().entries}")
  @support.require(en_first.body == b"Hello", "English variant body")
  @support.require(zh_first.body == b"Ni hao", "Chinese variant body")
  @support.require(en_again.source is CacheSource, "English must hit")
  @support.require(en_again.body == b"Hello", "English variant selection")
  @support.require(origin.call_count() == 2, "two variants need two fetches")
  @support.require(store.stats().entries == 2, "two variants must be stored")
}

///|
fn main {
  try! run()
}
