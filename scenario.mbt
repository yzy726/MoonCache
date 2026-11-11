///|
#derive(Eq, Debug, FromJson(fields(http_method(rename="method"))), ToJson(fields(http_method(rename="method"))))
pub(all) struct ScenarioRequest {
  http_method : String
  uri : String
  headers : Map[String, String]
  request_time : Int32?
}

///|
#derive(Eq, Debug, FromJson, ToJson)
pub(all) struct ScenarioResponse {
  status : Int32
  headers : Map[String, String]
  request_time : Int32?
  response_time : Int32?
  body : String?
  complete : Bool?
}

///|
#derive(Eq, Debug, FromJson, ToJson)
pub(all) struct ScenarioExpected {
  action : String
  reason : String?
}

///|
/// Stable, transport-free scenario format used by unit tests and the CLI.
#derive(Eq, Debug, FromJson, ToJson)
pub(all) struct CacheScenario {
  name : String
  mode : String
  now : Int32
  request : ScenarioRequest
  stored_response : ScenarioResponse?
  upstream_response : ScenarioResponse?
  expected : ScenarioExpected?
}

///|
#derive(Eq, Debug)
pub suberror ScenarioError {
  ScenarioError(String)
}

///|
pub fn ScenarioError::message(self : ScenarioError) -> String {
  match self {
    ScenarioError(message) => message
  }
}

///|
pub fn parse_scenario(text : String) -> CacheScenario raise ScenarioError {
  let json = @json.parse(text) catch {
    error => raise ScenarioError(error.to_string())
  }
  @json.from_json(json) catch {
    error => raise ScenarioError(error.to_string())
  }
}

///|
pub fn scenario_to_json(scenario : CacheScenario) -> String {
  ToJson::to_json(scenario).stringify(indent=2)
}

///|
pub fn ScenarioRequest::to_meta(self : ScenarioRequest) -> RequestMeta {
  let headers = HeaderMap::new()
  self.headers.each(fn(name, value) { ignore(headers.set(name, value)) })
  RequestMeta::new(
    self.http_method,
    self.uri,
    headers,
    Timestamp::from_seconds(self.request_time.unwrap_or(0).to_int64()),
  )
}

///|
pub fn ScenarioResponse::to_meta(
  self : ScenarioResponse,
  fallback_request_time : Timestamp,
) -> ResponseMeta {
  let headers = HeaderMap::new()
  self.headers.each(fn(name, value) { ignore(headers.set(name, value)) })
  let request_time = match self.request_time {
    Some(value) => Timestamp::from_seconds(value.to_int64())
    None => fallback_request_time
  }
  ResponseMeta::new(
    self.status,
    headers,
    request_time,
    match self.response_time {
      Some(value) => Timestamp::from_seconds(value.to_int64())
      None => request_time
    },
    self.complete.unwrap_or(true),
  )
}

///|
pub fn ScenarioResponse::body_bytes(self : ScenarioResponse) -> Bytes {
  match self.body {
    Some(body) => b"\{body}"
    None => b""
  }
}

///|
pub extend CacheScenario with @debug.Debug::{to_repr}

///|
pub extend CacheScenario with @json.ToJson::{to_json}

///|
pub extend CacheScenario with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend CacheScenario with Eq::{not_equal, equal}

///|
pub extend ScenarioError with @debug.Debug::{to_repr}

///|
pub extend ScenarioError with Eq::{not_equal, equal}

///|
pub extend ScenarioExpected with @debug.Debug::{to_repr}

///|
pub extend ScenarioExpected with @json.ToJson::{to_json}

///|
pub extend ScenarioExpected with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend ScenarioExpected with Eq::{not_equal, equal}

///|
pub extend ScenarioRequest with @debug.Debug::{to_repr}

///|
pub extend ScenarioRequest with @json.ToJson::{to_json}

///|
pub extend ScenarioRequest with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend ScenarioRequest with Eq::{not_equal, equal}

///|
pub extend ScenarioResponse with @debug.Debug::{to_repr}

///|
pub extend ScenarioResponse with @json.ToJson::{to_json}

///|
pub extend ScenarioResponse with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend ScenarioResponse with Eq::{not_equal, equal}
