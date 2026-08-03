///|
test "scenario JSON parses and normalizes metadata" {
  let text =
    #|{"name":"basic","mode":"private","now":10,"request":{"method":"get","uri":"https://example.test/data","headers":{"Accept":"application/json"},"request_time":1},"expected":{"action":"fetch","reason":"MC_RUNTIME_002"}}
  let scenario = @MoonCache.parse_scenario(text) catch {
    error => fail(error.message())
  }
  assert_eq(scenario.name, "basic")
  assert_eq(scenario.now, 10)
  let request = scenario.request.to_meta()
  assert_eq(request.http_method, "GET")
  assert_eq(request.headers.get("accept"), Some("application/json"))
}

///|
test "scenario response supplies deterministic defaults" {
  let response = @MoonCache.ScenarioResponse::{
    status: 200,
    headers: Map([]),
    request_time: None,
    response_time: None,
    body: None,
    complete: None,
  }
  let meta = response.to_meta(@MoonCache.Timestamp::from_seconds(7))
  assert_eq(meta.request_time.seconds(), 7)
  assert_eq(meta.response_time.seconds(), 7)
  assert_true(meta.body_complete)
  assert_eq(response.body_bytes(), b"")
}

///|
test "scenario JSON serializer round trips" {
  let scenario = @MoonCache.CacheScenario::{
    name: "round trip",
    mode: "shared",
    now: 42,
    request: @MoonCache.ScenarioRequest::{
      http_method: "GET",
      uri: "https://example.test/",
      headers: { "Accept": "*/*" },
      request_time: Some(1),
    },
    stored_response: None,
    upstream_response: None,
    expected: Some(@MoonCache.ScenarioExpected::{
      action: "fetch",
      reason: Some("MC_RUNTIME_002"),
    }),
  }
  let encoded = @MoonCache.scenario_to_json(scenario)
  let decoded = try! @MoonCache.parse_scenario(encoded)
  assert_eq(decoded, scenario)
}

///|
test "invalid scenario JSON raises a typed error" {
  let result : Result[@MoonCache.CacheScenario, @MoonCache.ScenarioError] = Ok(
    @MoonCache.parse_scenario("{"),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(_))
}
