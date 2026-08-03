///|
test "Vary parser defaults to no fields" {
  let vary = @MoonCache.parse_vary(policy_headers([]))
  assert_false(vary.star)
  assert_eq(vary.fields, [])
}

///|
test "Vary parser normalizes sorts and deduplicates fields" {
  let vary = @MoonCache.parse_vary(
    policy_headers([("Vary", "User-Agent, ACCEPT-LANGUAGE, user-agent")]),
  )
  assert_eq(vary.fields, ["accept-language", "user-agent"])
}

///|
test "Vary parser recognizes star" {
  let vary = @MoonCache.parse_vary(policy_headers([("Vary", "accept, *")]))
  assert_true(vary.star)
  assert_eq(vary.fields, [])
}

///|
test "default variant key is stable" {
  let key = @MoonCache.build_variant_key(
    policy_headers([]),
    @MoonCache.VarySpec::default(),
  ).unwrap()
  assert_eq(key, @MoonCache.VariantKey::empty())
}

///|
test "single Vary field matches equal values" {
  let stored = policy_request("GET", [("Accept-Language", "en")])
  let candidate = policy_request("GET", [("accept-language", "en")])
  let response = policy_response(200, [("Vary", "Accept-Language")], 0, 0, true)
  let result = @MoonCache.match_vary(stored, candidate, response)
  assert_true(result.kind is VaryMatchedResult)
}

///|
test "single Vary field rejects unequal values" {
  let stored = policy_request("GET", [("Accept-Language", "en")])
  let candidate = policy_request("GET", [("Accept-Language", "zh")])
  let response = policy_response(200, [("Vary", "Accept-Language")], 0, 0, true)
  let result = @MoonCache.match_vary(stored, candidate, response)
  assert_true(result.kind is VaryMismatchResult)
  assert_eq(result.differing_field, Some("accept-language"))
}

///|
test "multiple Vary fields must all match" {
  let stored = policy_request("GET", [
    ("Accept", "text/plain"),
    ("Accept-Language", "en"),
  ])
  let candidate = policy_request("GET", [
    ("Accept", "text/plain"),
    ("Accept-Language", "zh"),
  ])
  let response = policy_response(
    200,
    [("Vary", "Accept, Accept-Language")],
    0,
    0,
    true,
  )
  assert_true(
    @MoonCache.match_vary(stored, candidate, response).kind
    is VaryMismatchResult,
  )
}

///|
test "non-Vary request fields do not affect match" {
  let stored = policy_request("GET", [
    ("Accept-Language", "en"),
    ("X-Ignored", "one"),
  ])
  let candidate = policy_request("GET", [
    ("Accept-Language", "en"),
    ("X-Ignored", "two"),
  ])
  let response = policy_response(200, [("Vary", "Accept-Language")], 0, 0, true)
  assert_true(
    @MoonCache.match_vary(stored, candidate, response).kind is VaryMatchedResult,
  )
}

///|
test "Vary distinguishes missing and empty fields" {
  let stored = policy_request("GET", [])
  let candidate = policy_request("GET", [("Accept-Language", "")])
  let response = policy_response(200, [("Vary", "Accept-Language")], 0, 0, true)
  let result = @MoonCache.match_vary(stored, candidate, response)
  assert_true(result.kind is VaryMismatchResult)
  assert_eq(result.reason.code.code(), "MC_VARY_005")
}

///|
test "Vary matches when field is missing from both requests" {
  let stored = policy_request("GET", [])
  let candidate = policy_request("GET", [])
  let response = policy_response(200, [("Vary", "Accept-Language")], 0, 0, true)
  assert_true(
    @MoonCache.match_vary(stored, candidate, response).kind is VaryMatchedResult,
  )
}

///|
test "Vary repeated values match in equal order" {
  let stored = policy_request("GET", [
    ("Accept", "text/plain"),
    ("Accept", "application/json"),
  ])
  let candidate = policy_request("GET", [
    ("Accept", "text/plain"),
    ("Accept", "application/json"),
  ])
  let response = policy_response(200, [("Vary", "Accept")], 0, 0, true)
  assert_true(
    @MoonCache.match_vary(stored, candidate, response).kind is VaryMatchedResult,
  )
}

///|
test "Vary repeated value order remains significant" {
  let stored = policy_request("GET", [
    ("Accept", "text/plain"),
    ("Accept", "application/json"),
  ])
  let candidate = policy_request("GET", [
    ("Accept", "application/json"),
    ("Accept", "text/plain"),
  ])
  let response = policy_response(200, [("Vary", "Accept")], 0, 0, true)
  assert_true(
    @MoonCache.match_vary(stored, candidate, response).kind
    is VaryMismatchResult,
  )
}

///|
test "variant length encoding avoids delimiter collisions" {
  let vary = @MoonCache.parse_vary(policy_headers([("Vary", "X-Test")]))
  let first = @MoonCache.build_variant_key(
    policy_headers([("X-Test", "a:b;c")]),
    vary,
  ).unwrap()
  let second = @MoonCache.build_variant_key(
    policy_headers([("X-Test", "a"), ("X-Test", "b;c")]),
    vary,
  ).unwrap()
  assert_false(first == second)
}

///|
test "Vary star never matches" {
  let request = policy_request("GET", [])
  let response = policy_response(200, [("Vary", "*")], 0, 0, true)
  let result = @MoonCache.match_vary(request, request, response)
  assert_true(result.kind is VaryStarResult)
}

///|
test "variant selection picks matching language" {
  let english = policy_entry(
    [("Accept-Language", "en")],
    [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
    b"english",
    1,
  )
  let chinese = policy_entry(
    [("Accept-Language", "zh")],
    [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
    b"chinese",
    2,
  )
  let selected = @MoonCache.select_variant(
    [english, chinese],
    policy_request("GET", [("Accept-Language", "zh")]),
  )
  assert_eq(selected.entry.unwrap().body, b"chinese")
  assert_eq(selected.inspected, 2)
}

///|
test "variant selection chooses newest duplicate match" {
  let older = policy_entry(
    [("Accept-Language", "en")],
    [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
    b"old",
    1,
  )
  let newer = policy_entry(
    [("Accept-Language", "en")],
    [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
    b"new",
    2,
  )
  let selected = @MoonCache.select_variant(
    [older, newer],
    policy_request("GET", [("Accept-Language", "en")]),
  )
  assert_eq(selected.entry.unwrap().body, b"new")
}

///|
test "variant selection returns none when no variant matches" {
  let english = policy_entry(
    [("Accept-Language", "en")],
    [("Cache-Control", "max-age=60"), ("Vary", "Accept-Language")],
    b"english",
    1,
  )
  let selected = @MoonCache.select_variant(
    [english],
    policy_request("GET", [("Accept-Language", "zh")]),
  )
  assert_eq(selected.entry, None)
}
