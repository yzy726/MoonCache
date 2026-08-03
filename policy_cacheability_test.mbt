///|
test "storage accepts default-cacheable GET 200" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(200, [], 0, 0, true),
    private_options(),
  )
  assert_true(decision.storable)
  assert_true(reason_codes(decision.reasons).contains("MC_STORE_001"))
  assert_true(reason_codes(decision.reasons).contains("MC_STORE_004"))
}

///|
test "storage accepts HEAD by default" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("HEAD", []),
    policy_response(200, [], 0, 0, true),
    private_options(),
  )
  assert_true(decision.storable)
}

///|
test "storage rejects unsupported methods" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("POST", []),
    policy_response(200, [], 0, 0, true),
    private_options(),
  )
  assert_false(decision.storable)
  assert_eq(decision.reasons[0].code.code(), "MC_STORE_003")
}

///|
test "storage can disable HEAD response caching" {
  let options = private_options().with_cache_head_responses(false)
  let decision = @MoonCache.evaluate_storage(
    policy_request("HEAD", []),
    policy_response(200, [], 0, 0, true),
    options,
  )
  assert_false(decision.storable)
}

///|
test "storage rejects response no-store" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(200, [("Cache-Control", "no-store")], 0, 0, true),
    private_options(),
  )
  assert_false(decision.storable)
  assert_eq(decision.reasons[0].code.code(), "MC_STORE_002")
}

///|
test "storage rejects request no-store" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", [("Cache-Control", "no-store")]),
    policy_response(200, [], 0, 0, true),
    private_options(),
  )
  assert_false(decision.storable)
  assert_eq(decision.reasons[0].code.code(), "MC_STORE_002")
}

///|
test "storage rejects incomplete responses" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(200, [("Cache-Control", "max-age=60")], 0, 0, false),
    private_options(),
  )
  assert_false(decision.storable)
  assert_eq(decision.reasons[0].code.code(), "MC_STORE_008")
}

///|
test "storage rejects Vary star" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(200, [("Vary", "*")], 0, 0, true),
    private_options(),
  )
  assert_false(decision.storable)
  assert_eq(decision.reasons[0].code.code(), "MC_VARY_004")
}

///|
test "shared storage rejects private responses" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(200, [("Cache-Control", "private")], 0, 0, true),
    shared_options(),
  )
  assert_false(decision.storable)
  assert_eq(decision.reasons[0].code.code(), "MC_STORE_007")
}

///|
test "private cache accepts private responses" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(200, [("Cache-Control", "private")], 0, 0, true),
    private_options(),
  )
  assert_true(decision.storable)
  assert_true(decision.policy.is_private)
}

///|
test "shared storage rejects ordinary authorized requests" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", [("Authorization", "Bearer secret")]),
    policy_response(200, [("Cache-Control", "max-age=60")], 0, 0, true),
    shared_options(),
  )
  assert_false(decision.storable)
  assert_eq(decision.reasons[0].code.code(), "MC_AUTH_001")
}

///|
test "shared storage accepts authorized response marked public" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", [("Authorization", "Bearer secret")]),
    policy_response(200, [("Cache-Control", "public, max-age=60")], 0, 0, true),
    shared_options(),
  )
  assert_true(decision.storable)
}

///|
test "shared storage accepts authorized response with s-maxage" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", [("Authorization", "Bearer secret")]),
    policy_response(200, [("Cache-Control", "s-maxage=60")], 0, 0, true),
    shared_options(),
  )
  assert_true(decision.storable)
}

///|
test "shared authorization override is explicit" {
  let options = shared_options().with_shared_authorized(true)
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", [("Authorization", "Bearer secret")]),
    policy_response(200, [], 0, 0, true),
    options,
  )
  assert_true(decision.storable)
}

///|
test "storage rejects 302 without explicit caching metadata" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(302, [], 0, 0, true),
    private_options(),
  )
  assert_false(decision.storable)
  assert_eq(decision.reasons[0].code.code(), "MC_STORE_006")
}

///|
test "storage accepts 302 with explicit max-age" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(302, [("Cache-Control", "max-age=60")], 0, 0, true),
    private_options(),
  )
  assert_true(decision.storable)
  assert_true(reason_codes(decision.reasons).contains("MC_STORE_005"))
}

///|
test "storage accepts default-cacheable 404" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(404, [], 0, 0, true),
    private_options(),
  )
  assert_true(decision.storable)
}

///|
test "storage rejects partial content in initial scope" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(206, [("Cache-Control", "max-age=60")], 0, 0, true),
    private_options(),
  )
  assert_false(decision.storable)
}

///|
test "storage rejects status outside HTTP range" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(700, [("Cache-Control", "max-age=60")], 0, 0, true),
    private_options(),
  )
  assert_false(decision.storable)
}

///|
test "storage allows no-cache but marks revalidation required" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(200, [("Cache-Control", "no-cache")], 0, 0, true),
    private_options(),
  )
  assert_true(decision.storable)
  assert_true(decision.policy.requires_revalidation)
}

///|
test "shared private dominates simultaneous public" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(200, [("Cache-Control", "private, public")], 0, 0, true),
    shared_options(),
  )
  assert_false(decision.storable)
}

///|
test "stored policy records shared freshness lifetime" {
  let decision = @MoonCache.evaluate_storage(
    policy_request("GET", []),
    policy_response(
      200,
      [("Cache-Control", "max-age=10, s-maxage=90")],
      0,
      0,
      true,
    ),
    shared_options(),
  )
  assert_true(decision.storable)
  assert_eq(decision.policy.freshness_lifetime.seconds(), 90)
}
