///|
fn stale_policy_for(
  request_headers : Array[(String, String)],
  response_headers : Array[(String, String)],
  now : Int64,
  shared? : Bool = false,
) -> @MoonCache.StalePolicy {
  @MoonCache.evaluate_stale_policy(
    policy_request("GET", request_headers),
    policy_response(200, response_headers, 0, 0, true),
    if shared {
      shared_options()
    } else {
      private_options()
    },
    @MoonCache.Timestamp::from_seconds(now),
  )
}

///|
test "stale-if-error permits the exact staleness boundary" {
  let policy = stale_policy_for(
    [],
    [("Cache-Control", "max-age=10, stale-if-error=20")],
    30,
  )
  assert_true(policy.is_stale)
  assert_eq(policy.stale_by.seconds(), 20)
  assert_true(policy.stale_if_error_allowed)
}

///|
test "stale-if-error rejects a response beyond its window" {
  let policy = stale_policy_for(
    [],
    [("Cache-Control", "max-age=10, stale-if-error=20")],
    31,
  )
  assert_false(policy.stale_if_error_allowed)
}

///|
test "request stale-if-error can permit an applicable cached response" {
  let policy = stale_policy_for(
    [("Cache-Control", "stale-if-error=15")],
    [("Cache-Control", "max-age=10")],
    20,
  )
  assert_true(policy.stale_if_error_allowed)
  assert_eq(policy.stale_if_error_window.unwrap().seconds(), 15)
}

///|
test "request and response stale-if-error use the smaller window" {
  let policy = stale_policy_for(
    [("Cache-Control", "stale-if-error=5")],
    [("Cache-Control", "max-age=10, stale-if-error=30")],
    16,
  )
  assert_eq(policy.stale_if_error_window.unwrap().seconds(), 5)
  assert_false(policy.stale_if_error_allowed)
}

///|
test "stale-while-revalidate is response scoped and bounded" {
  let inside = stale_policy_for(
    [],
    [("Cache-Control", "max-age=10, stale-while-revalidate=20")],
    30,
  )
  let outside = stale_policy_for(
    [],
    [("Cache-Control", "max-age=10, stale-while-revalidate=20")],
    31,
  )
  assert_true(inside.stale_while_revalidate_allowed)
  assert_false(outside.stale_while_revalidate_allowed)
}

///|
test "fresh responses do not activate stale extensions" {
  let policy = stale_policy_for(
    [],
    [
      (
        "Cache-Control", "max-age=60, stale-if-error=20, stale-while-revalidate=20",
      ),
    ],
    10,
  )
  assert_false(policy.is_stale)
  assert_false(policy.stale_if_error_allowed)
  assert_false(policy.stale_while_revalidate_allowed)
}

///|
test "must-revalidate prohibits both stale extensions" {
  let policy = stale_policy_for(
    [],
    [
      (
        "Cache-Control", "max-age=10, must-revalidate, stale-if-error=30, stale-while-revalidate=30",
      ),
    ],
    20,
  )
  assert_true(policy.prohibited)
  assert_false(policy.stale_if_error_allowed)
  assert_false(policy.stale_while_revalidate_allowed)
}

///|
test "proxy-revalidate only prohibits stale extensions in shared mode" {
  let headers = [
    ("Cache-Control", "max-age=10, proxy-revalidate, stale-if-error=30"),
  ]
  assert_true(stale_policy_for([], headers, 20, shared=true).prohibited)
  assert_true(stale_policy_for([], headers, 20).stale_if_error_allowed)
}

///|
test "request no-cache and only-if-cached prohibit stale extensions" {
  let response = [("Cache-Control", "max-age=10, stale-if-error=30")]
  assert_true(
    stale_policy_for([("Cache-Control", "no-cache")], response, 20).prohibited,
  )
  assert_true(
    stale_policy_for([("Cache-Control", "only-if-cached")], response, 20).prohibited,
  )
}

///|
test "stale-if-error status classification follows RFC 5861" {
  for status in [500, 502, 503, 504] {
    assert_true(@MoonCache.is_stale_if_error_status(status))
  }
  for status in [200, 404, 501, 505] {
    assert_false(@MoonCache.is_stale_if_error_status(status))
  }
}
