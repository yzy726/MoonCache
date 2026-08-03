///|
fn run() -> Unit raise {
  let store = @mooncache.MemoryStore::default()
  let origin = @mooncache.RecordingTransport::new([
    @support.response(
      200,
      [("Cache-Control", "max-age=10"), ("ETag", "\"asset-v1\"")],
      b"version one",
      0L,
      0L,
    ),
    @support.response(
      304,
      [("Cache-Control", "max-age=60"), ("ETag", "\"asset-v1\"")],
      b"",
      20L,
      20L,
    ),
  ])
  let runtime = @mooncache.CachedRuntime::new(
    store,
    origin,
    @mooncache.CacheOptions::private_cache(),
  )
  let request = @mooncache.RuntimeRequest::get("https://example.test/asset")
  let initial = runtime.execute(request, @mooncache.Timestamp::zero())
  let validated = runtime.execute(
    request,
    @mooncache.Timestamp::from_seconds(20L),
  )
  let conditional = origin.calls()[1].meta.headers.get("if-none-match")
  let conditional_label = conditional.unwrap_or("<missing>")
  println("etag_revalidation")
  @support.print_result("initial", initial)
  @support.print_result("after expiry", validated)
  println("If-None-Match: \{conditional_label}")
  println("origin calls: \{origin.call_count()}")
  @support.require(
    validated.source is RevalidatedSource,
    "stale ETag entry must revalidate",
  )
  @support.require(
    conditional == Some("\"asset-v1\""),
    "conditional request must carry the ETag",
  )
  @support.require(
    validated.body == b"version one",
    "304 must retain the cached body",
  )
  @support.require(origin.call_count() == 2, "origin must see validation")
}

///|
fn main {
  try! run()
}
