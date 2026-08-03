///|
pub(all) struct ScenarioAnalysis {
  name : String
  trace : CacheTrace
  valid : Bool
  errors : Array[String]
} derive(Eq, Debug)

///|
fn scenario_mode(value : String) -> CacheMode raise ScenarioError {
  match CacheMode::from_string(value) {
    Some(mode) => mode
    None => raise ScenarioError("mode must be private or shared")
  }
}

///|
fn scenario_action_matches(expected : String, actual : CacheActionKind) -> Bool {
  let value = expected
    .trim(chars=" \t")
    .to_lower()
    .replace_all(old="-", new="_")
  match actual {
    ServeFresh => value == "serve_fresh" || value == "fresh" || value == "hit"
    Revalidate => value == "revalidate"
    Fetch => value == "fetch" || value == "miss"
    ServeStale => value == "serve_stale" || value == "stale"
    Bypass => value == "bypass"
    OnlyIfCachedMiss =>
      value == "only_if_cached_miss" || value == "only_if_cached"
  }
}

///|
fn trace_for_scenario_miss(
  request : RequestMeta,
  policy : RequestPolicy,
) -> CacheTrace {
  let action = if policy.bypass {
    Bypass
  } else if policy.only_if_cached {
    OnlyIfCachedMiss
  } else {
    Fetch
  }
  let trace = CacheTrace::new(action)
  match primary_cache_key(request) {
    Some(key) => trace.primary_key = Some(key.label())
    None => ()
  }
  match action {
    Bypass => {
      trace.add_reason(CacheReason::new(RequestNoStore))
      trace.add_reason(CacheReason::new(RuntimeBypass))
    }
    OnlyIfCachedMiss => {
      trace.add_reason(CacheReason::new(RequestOnlyIfCached))
      trace.add_reason(CacheReason::new(RuntimeOnlyIfCachedMiss))
    }
    Fetch => {
      trace.add_reason(CacheReason::new(RuntimeMiss))
      trace.add_reason(CacheReason::new(RuntimeFetch))
    }
    _ => ()
  }
  trace
}

///|
fn trace_for_stored_scenario(
  scenario : CacheScenario,
  request : RequestMeta,
  response_data : ScenarioResponse,
  options : CacheOptions,
) -> CacheTrace {
  let response = response_data.to_meta(request.request_time)
  let decision = evaluate_cached_response(
    request,
    response,
    options,
    Timestamp::from_seconds(scenario.now.to_int64()),
  )
  let trace = decision.trace
  match primary_cache_key(request) {
    Some(key) => trace.primary_key = Some(key.label())
    None => ()
  }
  match build_variant_key(request.headers, parse_vary(response.headers)) {
    Some(variant) => trace.selected_variant = Some(variant.label)
    None => ()
  }
  match response_validator_kind(response) {
    Some(kind) => trace.validator = Some(kind.label())
    None => ()
  }
  trace
}

///|
pub fn analyze_scenario(
  scenario : CacheScenario,
) -> ScenarioAnalysis raise ScenarioError {
  let mode = scenario_mode(scenario.mode)
  let options = if mode is Shared {
    CacheOptions::shared_cache()
  } else {
    CacheOptions::private_cache()
  }
  let request = scenario.request.to_meta()
  let trace = match scenario.stored_response {
    Some(response) =>
      trace_for_stored_scenario(scenario, request, response, options)
    None => trace_for_scenario_miss(request, evaluate_request_policy(request))
  }
  let errors : Array[String] = []
  if scenario.name.trim().is_empty() {
    errors.push("name must not be empty")
  }
  if normalize_cache_uri(request.uri) is None {
    errors.push("request.uri must be an absolute HTTP(S) URI")
  }
  match scenario.stored_response {
    Some(response) =>
      if response.status < 100 || response.status > 599 {
        errors.push("stored_response.status must be between 100 and 599")
      }
    None => ()
  }
  match scenario.expected {
    Some(expected) => {
      if !scenario_action_matches(expected.action, trace.action) {
        errors.push(
          "expected action \{expected.action}, got \{trace.action.label()}",
        )
      }
      match expected.reason {
        Some(code) =>
          if !trace.reasons.any(fn(reason) { reason.code.code() == code }) {
            errors.push("expected reason \{code} was not emitted")
          }
        None => ()
      }
    }
    None => ()
  }
  ScenarioAnalysis::{
    name: scenario.name,
    trace,
    valid: errors.length() == 0,
    errors,
  }
}

///|
pub fn analyze_scenario_json(
  text : String,
) -> ScenarioAnalysis raise ScenarioError {
  analyze_scenario(parse_scenario(text))
}

///|
pub fn explain_scenario_text(text : String) -> String raise ScenarioError {
  let analysis = analyze_scenario_json(text)
  let report = analysis.trace.text_report()
  if analysis.errors.length() == 0 {
    report
  } else {
    let errors = analysis.errors.join("\n- ")
    "\{report}\nValidation errors:\n- \{errors}"
  }
}

///|
pub fn explain_scenario_json(text : String) -> String raise ScenarioError {
  analyze_scenario_json(text).trace.json_report()
}

///|
pub fn validate_scenario_text(text : String) -> String raise ScenarioError {
  let analysis = analyze_scenario_json(text)
  if analysis.valid {
    "VALID: \{analysis.name}"
  } else {
    let errors = analysis.errors.join("\n- ")
    "INVALID: \{analysis.name}\n- \{errors}"
  }
}
