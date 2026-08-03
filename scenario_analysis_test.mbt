///|
test "scenario analysis explains cache miss" {
  let text =
    #|{"name":"miss","mode":"private","now":0,"request":{"method":"GET","uri":"https://example.test/data","headers":{}},"expected":{"action":"fetch","reason":"MC_RUNTIME_002"}}
  let analysis = try! @MoonCache.analyze_scenario_json(text)
  assert_true(analysis.valid)
  assert_true(analysis.trace.action is Fetch)
}

///|
test "scenario analysis explains stale ETag revalidation" {
  let text =
    #|{"name":"stale etag","mode":"private","now":120,"request":{"method":"GET","uri":"https://example.test/data","headers":{}},"stored_response":{"status":200,"headers":{"Cache-Control":"max-age=60","ETag":"\"v1\""},"request_time":0,"response_time":0,"body":"cached","complete":true},"expected":{"action":"revalidate","reason":"MC_REVAL_001"}}
  let analysis = try! @MoonCache.analyze_scenario_json(text)
  assert_true(analysis.valid)
  assert_true(analysis.trace.action is Revalidate)
  assert_eq(analysis.trace.validator, Some("strong-etag"))
}

///|
test "scenario validation reports expectation mismatch" {
  let text =
    #|{"name":"wrong expected","mode":"private","now":0,"request":{"method":"GET","uri":"https://example.test/data","headers":{}},"expected":{"action":"serve_fresh"}}
  let analysis = try! @MoonCache.analyze_scenario_json(text)
  assert_false(analysis.valid)
  assert_true(analysis.errors[0].contains("expected action"))
}

///|
test "scenario validation rejects relative URI" {
  let text =
    #|{"name":"bad uri","mode":"private","now":0,"request":{"method":"GET","uri":"/relative","headers":{}}}
  let analysis = try! @MoonCache.analyze_scenario_json(text)
  assert_false(analysis.valid)
  assert_true(analysis.errors[0].contains("absolute HTTP(S) URI"))
}

///|
test "scenario text report includes decision arithmetic" {
  let text =
    #|{"name":"fresh","mode":"private","now":10,"request":{"method":"GET","uri":"https://example.test/data","headers":{}},"stored_response":{"status":200,"headers":{"Cache-Control":"max-age=60"},"request_time":0,"response_time":0,"body":"cached","complete":true}}
  let report = try! @MoonCache.explain_scenario_text(text)
  assert_true(report.contains("Decision: SERVE_FRESH"))
  assert_true(report.contains("Current age: 10s"))
}

///|
test "scenario JSON report is structured" {
  let text =
    #|{"name":"miss","mode":"shared","now":0,"request":{"method":"GET","uri":"https://example.test/data","headers":{}}}
  let report = try! @MoonCache.explain_scenario_json(text)
  assert_true(report.contains("\"action\": \"FETCH\""))
  assert_true(report.contains("\"primary_key\""))
}
