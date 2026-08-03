///|
fn cached_decision(
  request_pairs : Array[(String, String)],
  response_pairs : Array[(String, String)],
  now : Int64,
) -> @MoonCache.CacheDecision {
  @MoonCache.evaluate_cached_response(
    policy_request("GET", request_pairs),
    policy_response(200, response_pairs, 0, 0, true),
    private_options(),
    @MoonCache.Timestamp::from_seconds(now),
  )
}

///|
test "policy serves a fresh response" {
  let decision = cached_decision([], [("Cache-Control", "max-age=60")], 30)
  assert_true(decision.action is ServeFresh)
  assert_true(decision.trace.has_reason(RuntimeHit))
}

///|
test "policy treats freshness boundary as stale" {
  let decision = cached_decision([], [("Cache-Control", "max-age=60")], 60)
  assert_true(decision.action is Fetch)
  assert_eq(decision.trace.stale_by.unwrap().seconds(), 0)
}

///|
test "policy revalidates stale ETag response" {
  let decision = cached_decision(
    [],
    [("Cache-Control", "max-age=10"), ("ETag", "\"v1\"")],
    20,
  )
  assert_true(decision.action is Revalidate)
}

///|
test "policy revalidates stale Last-Modified response" {
  let decision = cached_decision(
    [],
    [
      ("Cache-Control", "max-age=10"),
      ("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT"),
    ],
    20,
  )
  assert_true(decision.action is Revalidate)
}

///|
test "policy fetches stale response without validator" {
  let decision = cached_decision([], [("Cache-Control", "max-age=10")], 20)
  assert_true(decision.action is Fetch)
}

///|
test "request no-cache forces validation while fresh" {
  let decision = cached_decision(
    [("Cache-Control", "no-cache")],
    [("Cache-Control", "max-age=60"), ("ETag", "\"v1\"")],
    10,
  )
  assert_true(decision.action is Revalidate)
  assert_true(decision.trace.has_reason(RequestNoCache))
}

///|
test "response no-cache forces validation while fresh" {
  let decision = cached_decision(
    [],
    [("Cache-Control", "no-cache, max-age=60"), ("ETag", "\"v1\"")],
    10,
  )
  assert_true(decision.action is Revalidate)
}

///|
test "request no-store bypasses cached response" {
  let decision = cached_decision(
    [("Cache-Control", "no-store")],
    [("Cache-Control", "max-age=60")],
    10,
  )
  assert_true(decision.action is Bypass)
  assert_true(decision.trace.has_reason(RuntimeBypass))
}

///|
test "only-if-cached still permits a fresh hit" {
  let decision = cached_decision(
    [("Cache-Control", "only-if-cached")],
    [("Cache-Control", "max-age=60")],
    10,
  )
  assert_true(decision.action is ServeFresh)
}

///|
test "only-if-cached stale response avoids upstream" {
  let decision = cached_decision(
    [("Cache-Control", "only-if-cached")],
    [("Cache-Control", "max-age=10"), ("ETag", "\"v1\"")],
    20,
  )
  assert_true(decision.action is OnlyIfCachedMiss)
}

///|
test "request max-age tightens response lifetime" {
  let decision = cached_decision(
    [("Cache-Control", "max-age=10")],
    [("Cache-Control", "max-age=60")],
    20,
  )
  assert_true(decision.action is Fetch)
  assert_eq(decision.trace.freshness_lifetime.unwrap().seconds(), 10)
}

///|
test "request min-fresh can make response unusable" {
  let decision = cached_decision(
    [("Cache-Control", "min-fresh=15")],
    [("Cache-Control", "max-age=60")],
    50,
  )
  assert_true(decision.action is Fetch)
  assert_true(decision.trace.has_reason(RequestMinFresh))
}

///|
test "bounded max-stale permits response within window" {
  let decision = cached_decision(
    [("Cache-Control", "max-stale=15")],
    [("Cache-Control", "max-age=10")],
    20,
  )
  assert_true(decision.action is ServeStale)
}

///|
test "bounded max-stale rejects response outside window" {
  let decision = cached_decision(
    [("Cache-Control", "max-stale=5")],
    [("Cache-Control", "max-age=10"), ("ETag", "\"v1\"")],
    20,
  )
  assert_true(decision.action is Revalidate)
}

///|
test "unbounded max-stale permits stale response" {
  let decision = cached_decision(
    [("Cache-Control", "max-stale")],
    [("Cache-Control", "max-age=0")],
    1_000,
  )
  assert_true(decision.action is ServeStale)
}

///|
test "must-revalidate blocks max-stale" {
  let decision = cached_decision(
    [("Cache-Control", "max-stale")],
    [("Cache-Control", "max-age=10, must-revalidate"), ("ETag", "\"v1\"")],
    20,
  )
  assert_true(decision.action is Revalidate)
}

///|
test "proxy-revalidate blocks stale in shared cache" {
  let decision = @MoonCache.evaluate_cached_response(
    policy_request("GET", [("Cache-Control", "max-stale")]),
    policy_response(
      200,
      [("Cache-Control", "max-age=10, proxy-revalidate"), ("ETag", "\"v1\"")],
      0,
      0,
      true,
    ),
    shared_options(),
    @MoonCache.Timestamp::from_seconds(20),
  )
  assert_true(decision.action is Revalidate)
}

///|
test "proxy-revalidate does not block private max-stale" {
  let decision = cached_decision(
    [("Cache-Control", "max-stale")],
    [("Cache-Control", "max-age=10, proxy-revalidate")],
    20,
  )
  assert_true(decision.action is ServeStale)
}

///|
test "max-age zero is immediately stale" {
  let decision = cached_decision([], [("Cache-Control", "max-age=0")], 0)
  assert_true(decision.action is Fetch)
}

///|
test "uncacheable Vary star entry is fetched" {
  let decision = cached_decision(
    [],
    [("Cache-Control", "max-age=60"), ("Vary", "*")],
    10,
  )
  assert_true(decision.action is Fetch)
  assert_true(decision.trace.has_reason(StoreVaryStar))
}

///|
test "trace text explains age and reason code" {
  let decision = cached_decision([], [("Cache-Control", "max-age=60")], 10)
  let report = decision.trace.text_report()
  assert_true(report.contains("Decision: SERVE_FRESH"))
  assert_true(report.contains("Current age: 10s"))
  assert_true(report.contains("MC_RUNTIME_001"))
}

///|
test "trace JSON contains structured action and age" {
  let decision = cached_decision([], [("Cache-Control", "max-age=60")], 10)
  let report = decision.trace.json_report()
  assert_true(report.contains("\"action\": \"SERVE_FRESH\""))
  assert_true(report.contains("\"current_age\": 10"))
  assert_true(report.contains("\"reasons\""))
}
