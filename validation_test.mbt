///|
test "validator accepts strong ETag" {
  assert_true(@MoonCache.is_valid_etag("\"asset-v1\""))
}

///|
test "validator accepts weak ETag" {
  assert_true(@MoonCache.is_valid_etag("W/\"asset-v1\""))
}

///|
test "validator rejects unquoted ETag" {
  assert_false(@MoonCache.is_valid_etag("asset-v1"))
}

///|
test "validator rejects embedded quote" {
  assert_false(@MoonCache.is_valid_etag("\"asset\"v1\""))
}

///|
test "validator rejects newline injection" {
  assert_false(@MoonCache.is_valid_etag("\"asset\nheader\""))
}

///|
test "validator kind reports strong ETag" {
  let response = policy_response(200, [("ETag", "\"v1\"")], 0, 0, true)
  assert_true(@MoonCache.response_validator_kind(response) is Some(StrongEtag))
}

///|
test "validator kind reports weak ETag and Last-Modified" {
  let response = policy_response(
    200,
    [("ETag", "W/\"v1\""), ("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT")],
    0,
    0,
    true,
  )
  assert_true(
    @MoonCache.response_validator_kind(response)
    is Some(WeakEtagAndLastModified),
  )
}

///|
test "revalidation plan generates If-None-Match" {
  let plan = @MoonCache.create_revalidation_plan(
    policy_request("GET", []),
    policy_response(200, [("ETag", "\"v1\"")], 0, 0, true),
  )
  assert_eq(plan.request.headers.get("if-none-match"), Some("\"v1\""))
  assert_eq(plan.generated_headers.get("if-none-match"), Some("\"v1\""))
  assert_true(plan.validator_kind is Some(StrongEtag))
}

///|
test "revalidation plan preserves weak ETag" {
  let plan = @MoonCache.create_revalidation_plan(
    policy_request("GET", []),
    policy_response(200, [("ETag", "W/\"v1\"")], 0, 0, true),
  )
  assert_eq(plan.request.headers.get("if-none-match"), Some("W/\"v1\""))
  assert_true(plan.validator_kind is Some(WeakEtag))
}

///|
test "revalidation plan generates If-Modified-Since" {
  let date = "Thu, 01 Jan 1970 00:00:00 GMT"
  let plan = @MoonCache.create_revalidation_plan(
    policy_request("GET", []),
    policy_response(200, [("Last-Modified", date)], 0, 0, true),
  )
  assert_eq(plan.request.headers.get("if-modified-since"), Some(date))
  assert_true(plan.validator_kind is Some(LastModified))
}

///|
test "revalidation plan can generate both validators" {
  let date = "Thu, 01 Jan 1970 00:00:00 GMT"
  let plan = @MoonCache.create_revalidation_plan(
    policy_request("GET", []),
    policy_response(
      200,
      [("ETag", "\"v1\""), ("Last-Modified", date)],
      0,
      0,
      true,
    ),
  )
  assert_eq(plan.request.headers.get("if-none-match"), Some("\"v1\""))
  assert_eq(plan.request.headers.get("if-modified-since"), Some(date))
  assert_true(plan.validator_kind is Some(StrongEtagAndLastModified))
  assert_true(reason_codes(plan.reasons).contains("MC_REVAL_003"))
}

///|
test "revalidation plan never overwrites caller If-None-Match" {
  let plan = @MoonCache.create_revalidation_plan(
    policy_request("GET", [("If-None-Match", "\"caller\"")]),
    policy_response(200, [("ETag", "\"cached\"")], 0, 0, true),
  )
  assert_eq(plan.request.headers.get("if-none-match"), Some("\"caller\""))
  assert_false(plan.generated_headers.contains("if-none-match"))
  assert_true(reason_codes(plan.reasons).contains("MC_REVAL_004"))
}

///|
test "revalidation plan never overwrites caller If-Modified-Since" {
  let caller_date = "Thu, 01 Jan 1970 00:00:01 GMT"
  let cached_date = "Thu, 01 Jan 1970 00:00:00 GMT"
  let plan = @MoonCache.create_revalidation_plan(
    policy_request("GET", [("If-Modified-Since", caller_date)]),
    policy_response(200, [("Last-Modified", cached_date)], 0, 0, true),
  )
  assert_eq(plan.request.headers.get("if-modified-since"), Some(caller_date))
  assert_false(plan.generated_headers.contains("if-modified-since"))
}

///|
test "caller conditions alone make revalidation possible" {
  let plan = @MoonCache.create_revalidation_plan(
    policy_request("GET", [("If-None-Match", "\"caller\"")]),
    policy_response(200, [], 0, 0, true),
  )
  assert_true(plan.can_revalidate())
  assert_true(plan.validator_kind is Some(CallerConditions))
}

///|
test "missing validators cannot create revalidation plan" {
  let plan = @MoonCache.create_revalidation_plan(
    policy_request("GET", []),
    policy_response(200, [], 0, 0, true),
  )
  assert_false(plan.can_revalidate())
  assert_eq(plan.validator_kind, None)
}

///|
test "malformed cached validators are ignored" {
  let plan = @MoonCache.create_revalidation_plan(
    policy_request("GET", []),
    policy_response(
      200,
      [("ETag", "bad"), ("Last-Modified", "bad")],
      0,
      0,
      true,
    ),
  )
  assert_false(plan.can_revalidate())
}

///|
test "revalidation plan preserves unrelated request fields" {
  let plan = @MoonCache.create_revalidation_plan(
    policy_request("GET", [("Accept", "application/json")]),
    policy_response(200, [("ETag", "\"v1\"")], 0, 0, true),
  )
  assert_eq(plan.request.headers.get("accept"), Some("application/json"))
}
