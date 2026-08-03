///|
test "age calculation derives apparent age from Date" {
  let response = policy_response(
    200,
    [("Date", "Thu, 01 Jan 1970 00:00:00 GMT")],
    0,
    10,
    true,
  )
  let age = @MoonCache.calculate_current_age(
    response,
    @MoonCache.Timestamp::from_seconds(10),
  )
  assert_eq(age.apparent_age.seconds(), 10)
  assert_eq(age.current_age.seconds(), 10)
}

///|
test "age calculation adds response delay to Age header" {
  let response = policy_response(200, [("Age", "20")], 0, 10, true)
  let age = @MoonCache.calculate_current_age(
    response,
    @MoonCache.Timestamp::from_seconds(10),
  )
  assert_eq(age.response_delay.seconds(), 10)
  assert_eq(age.corrected_age_value.seconds(), 30)
}

///|
test "age calculation selects greatest corrected initial age" {
  let response = policy_response(
    200,
    [("Date", "Thu, 01 Jan 1970 00:00:00 GMT"), ("Age", "5")],
    15,
    20,
    true,
  )
  let age = @MoonCache.calculate_current_age(
    response,
    @MoonCache.Timestamp::from_seconds(20),
  )
  assert_eq(age.apparent_age.seconds(), 20)
  assert_eq(age.corrected_age_value.seconds(), 10)
  assert_eq(age.corrected_initial_age.seconds(), 20)
}

///|
test "age calculation adds resident time" {
  let response = policy_response(200, [("Age", "5")], 0, 0, true)
  let age = @MoonCache.calculate_current_age(
    response,
    @MoonCache.Timestamp::from_seconds(40),
  )
  assert_eq(age.resident_time.seconds(), 40)
  assert_eq(age.current_age.seconds(), 45)
}

///|
test "age calculation clamps future Date" {
  let response = policy_response(
    200,
    [("Date", "Thu, 01 Jan 1970 00:01:40 GMT")],
    0,
    10,
    true,
  )
  let age = @MoonCache.calculate_current_age(
    response,
    @MoonCache.Timestamp::from_seconds(10),
  )
  assert_eq(age.apparent_age.seconds(), 0)
  assert_true(age.clock_clamped)
}

///|
test "age calculation clamps backward response clock" {
  let response = policy_response(200, [], 20, 10, true)
  let age = @MoonCache.calculate_current_age(
    response,
    @MoonCache.Timestamp::from_seconds(10),
  )
  assert_eq(age.response_delay.seconds(), 0)
  assert_true(age.clock_clamped)
}

///|
test "age calculation clamps backward evaluation clock" {
  let response = policy_response(200, [], 0, 20, true)
  let age = @MoonCache.calculate_current_age(
    response,
    @MoonCache.Timestamp::from_seconds(10),
  )
  assert_eq(age.resident_time.seconds(), 0)
  assert_true(age.clock_clamped)
}

///|
test "age calculation saturates overflow" {
  let response = policy_response(
    200,
    [("Age", "9223372036854775807")],
    0,
    1,
    true,
  )
  let age = @MoonCache.calculate_current_age(
    response,
    @MoonCache.Timestamp::from_seconds(1),
  )
  assert_eq(age.current_age.seconds(), @MoonCache.MAX_DELTA_SECONDS)
  assert_true(age.overflow_clamped)
}

///|
test "age calculation ignores malformed Age" {
  let response = policy_response(200, [("Age", "invalid")], 0, 0, true)
  let age = @MoonCache.calculate_current_age(
    response,
    @MoonCache.Timestamp::from_seconds(0),
  )
  assert_eq(age.age_value.seconds(), 0)
}

///|
test "freshness uses max-age in private cache" {
  let response = policy_response(
    200,
    [("Cache-Control", "max-age=60")],
    0,
    0,
    true,
  )
  let fresh = @MoonCache.calculate_freshness_lifetime(
    response,
    private_options(),
  )
  assert_true(fresh.source is MaxAge)
  assert_eq(fresh.lifetime.seconds(), 60)
}

///|
test "freshness uses s-maxage in shared cache" {
  let response = policy_response(
    200,
    [("Cache-Control", "max-age=60, s-maxage=120")],
    0,
    0,
    true,
  )
  let fresh = @MoonCache.calculate_freshness_lifetime(
    response,
    shared_options(),
  )
  assert_true(fresh.source is SharedMaxAge)
  assert_eq(fresh.lifetime.seconds(), 120)
}

///|
test "private cache ignores s-maxage when max-age exists" {
  let response = policy_response(
    200,
    [("Cache-Control", "max-age=60, s-maxage=120")],
    0,
    0,
    true,
  )
  let fresh = @MoonCache.calculate_freshness_lifetime(
    response,
    private_options(),
  )
  assert_true(fresh.source is MaxAge)
  assert_eq(fresh.lifetime.seconds(), 60)
}

///|
test "private cache does not use s-maxage alone" {
  let response = policy_response(
    200,
    [("Cache-Control", "s-maxage=120")],
    0,
    0,
    true,
  )
  let fresh = @MoonCache.calculate_freshness_lifetime(
    response,
    private_options(),
  )
  assert_true(fresh.source is NoFreshness)
  assert_eq(fresh.lifetime.seconds(), 0)
}

///|
test "freshness derives lifetime from Expires and Date" {
  let response = policy_response(
    200,
    [
      ("Date", "Thu, 01 Jan 1970 00:00:00 GMT"),
      ("Expires", "Thu, 01 Jan 1970 00:01:00 GMT"),
    ],
    0,
    0,
    true,
  )
  let fresh = @MoonCache.calculate_freshness_lifetime(
    response,
    private_options(),
  )
  assert_true(fresh.source is Expires)
  assert_eq(fresh.lifetime.seconds(), 60)
}

///|
test "freshness clamps past Expires at zero" {
  let response = policy_response(
    200,
    [
      ("Date", "Thu, 01 Jan 1970 00:01:00 GMT"),
      ("Expires", "Thu, 01 Jan 1970 00:00:00 GMT"),
    ],
    0,
    60,
    true,
  )
  let fresh = @MoonCache.calculate_freshness_lifetime(
    response,
    private_options(),
  )
  assert_eq(fresh.lifetime.seconds(), 0)
}

///|
test "freshness treats invalid Expires as immediately stale" {
  let response = policy_response(200, [("Expires", "not-a-date")], 0, 0, true)
  let fresh = @MoonCache.calculate_freshness_lifetime(
    response,
    private_options(),
  )
  assert_true(fresh.source is Expires)
  assert_eq(fresh.lifetime.seconds(), 0)
}

///|
test "freshness uses ten percent Last-Modified heuristic" {
  let response = policy_response(
    200,
    [
      ("Date", "Thu, 01 Jan 1970 00:16:40 GMT"),
      ("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT"),
    ],
    0,
    1_000,
    true,
  )
  let fresh = @MoonCache.calculate_freshness_lifetime(
    response,
    private_options(),
  )
  assert_true(fresh.source is HeuristicLastModified)
  assert_eq(fresh.lifetime.seconds(), 100)
}

///|
test "freshness caps Last-Modified heuristic" {
  let response = policy_response(
    200,
    [
      ("Date", "Fri, 01 Jan 1971 00:00:00 GMT"),
      ("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT"),
    ],
    0,
    31_536_000,
    true,
  )
  let fresh = @MoonCache.calculate_freshness_lifetime(
    response,
    private_options(),
  )
  assert_eq(fresh.lifetime.seconds(), 86_400)
}

///|
test "freshness heuristic can be disabled" {
  let response = policy_response(
    200,
    [
      ("Date", "Thu, 01 Jan 1970 00:16:40 GMT"),
      ("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT"),
    ],
    0,
    1_000,
    true,
  )
  let options = private_options().with_heuristic_freshness(false)
  let fresh = @MoonCache.calculate_freshness_lifetime(response, options)
  assert_true(fresh.source is NoFreshness)
}

///|
test "freshness future Last-Modified yields zero heuristic" {
  let response = policy_response(
    200,
    [
      ("Date", "Thu, 01 Jan 1970 00:00:00 GMT"),
      ("Last-Modified", "Thu, 01 Jan 1970 00:01:00 GMT"),
    ],
    0,
    0,
    true,
  )
  let fresh = @MoonCache.calculate_freshness_lifetime(
    response,
    private_options(),
  )
  assert_eq(fresh.lifetime.seconds(), 0)
}

///|
test "freshness explicit max-age precedes Expires" {
  let response = policy_response(
    200,
    [
      ("Cache-Control", "max-age=30"),
      ("Date", "Thu, 01 Jan 1970 00:00:00 GMT"),
      ("Expires", "Thu, 01 Jan 1970 00:10:00 GMT"),
    ],
    0,
    0,
    true,
  )
  let fresh = @MoonCache.calculate_freshness_lifetime(
    response,
    private_options(),
  )
  assert_true(fresh.source is MaxAge)
  assert_eq(fresh.lifetime.seconds(), 30)
}

///|
test "freshness custom heuristic settings are honored" {
  let response = policy_response(
    200,
    [
      ("Date", "Thu, 01 Jan 1970 00:16:40 GMT"),
      ("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT"),
    ],
    0,
    1_000,
    true,
  )
  let options = private_options().with_heuristic_settings(
    500,
    @MoonCache.DeltaSeconds::from_seconds(200),
  )
  let fresh = @MoonCache.calculate_freshness_lifetime(response, options)
  assert_eq(fresh.lifetime.seconds(), 200)
}
