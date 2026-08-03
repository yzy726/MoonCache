///|
test "safe method does not invalidate" {
  let plan = @MoonCache.plan_invalidation(
    policy_request("GET", []),
    policy_response(200, [], 0, 0, true),
  )
  assert_eq(plan.uris, [])
  assert_eq(plan.reasons[0].code.code(), "MC_INV_003")
}

///|
test "successful POST invalidates target URI" {
  let plan = @MoonCache.plan_invalidation(
    policy_request("POST", []),
    policy_response(201, [], 0, 0, true),
  )
  assert_eq(plan.uris, ["https://example.test/data"])
  assert_eq(plan.reasons[0].code.code(), "MC_INV_001")
}

///|
test "successful DELETE invalidates target URI" {
  let plan = @MoonCache.plan_invalidation(
    policy_request("DELETE", []),
    policy_response(204, [], 0, 0, true),
  )
  assert_eq(plan.uris, ["https://example.test/data"])
}

///|
test "unsafe method error response does not invalidate" {
  let plan = @MoonCache.plan_invalidation(
    policy_request("PUT", []),
    policy_response(500, [], 0, 0, true),
  )
  assert_eq(plan.uris, [])
  assert_eq(plan.reasons[0].code.code(), "MC_INV_004")
}

///|
test "unsafe redirect response invalidates" {
  let plan = @MoonCache.plan_invalidation(
    policy_request("POST", []),
    policy_response(302, [], 0, 0, true),
  )
  assert_eq(plan.uris, ["https://example.test/data"])
}

///|
test "same-origin absolute Location is invalidated" {
  let plan = @MoonCache.plan_invalidation(
    policy_request("POST", []),
    policy_response(
      201,
      [("Location", "https://example.test/created")],
      0,
      0,
      true,
    ),
  )
  assert_eq(plan.uris, [
    "https://example.test/data", "https://example.test/created",
  ])
}

///|
test "cross-origin Location is excluded" {
  let plan = @MoonCache.plan_invalidation(
    policy_request("POST", []),
    policy_response(
      201,
      [("Location", "https://other.test/created")],
      0,
      0,
      true,
    ),
  )
  assert_eq(plan.uris, ["https://example.test/data"])
}

///|
test "root-relative Location is resolved" {
  let plan = @MoonCache.plan_invalidation(
    policy_request("POST", []),
    policy_response(201, [("Location", "/created")], 0, 0, true),
  )
  assert_eq(plan.uris, [
    "https://example.test/data", "https://example.test/created",
  ])
}

///|
test "path-relative Content-Location is resolved" {
  let request = @MoonCache.RequestMeta::simple(
    "PUT", "https://example.test/items/old",
  )
  let plan = @MoonCache.plan_invalidation(
    request,
    policy_response(200, [("Content-Location", "new")], 0, 0, true),
  )
  assert_eq(plan.uris, [
    "https://example.test/items/old", "https://example.test/items/new",
  ])
}

///|
test "related URI equal to target is deduplicated" {
  let plan = @MoonCache.plan_invalidation(
    policy_request("POST", []),
    policy_response(200, [("Location", "/data")], 0, 0, true),
  )
  assert_eq(plan.uris, ["https://example.test/data"])
}

///|
test "query-only related URI preserves target path" {
  assert_eq(
    @MoonCache.resolve_related_uri("https://example.test/data?old=1", "?new=2"),
    Some("https://example.test/data?new=2"),
  )
}
