///|
pub(all) struct ScenarioRequest {
  http_method : String
  uri : String
  headers : Map[String, String]
  request_time : Int?
} derive (
  Eq,
  Debug,
  FromJson(fields(http_method(rename="method"))),
  ToJson(fields(http_method(rename="method"))),
)

///|
pub(all) struct ScenarioResponse {
  status : Int
  headers : Map[String, String]
  request_time : Int?
  response_time : Int?
  body : String?
  complete : Bool?
} derive(Eq, Debug, FromJson, ToJson)

///|
pub(all) struct ScenarioExpected {
  action : String
  reason : String?
} derive(Eq, Debug, FromJson, ToJson)

///|
/// Stable, transport-free scenario format used by unit tests and the CLI.
pub(all) struct CacheScenario {
  name : String
  mode : String
  now : Int
  request : ScenarioRequest
  stored_response : ScenarioResponse?
  upstream_response : ScenarioResponse?
  expected : ScenarioExpected?
} derive(Eq, Debug, FromJson, ToJson)

///|
pub suberror ScenarioError {
  ScenarioError(String)
} derive(Eq, Debug)

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
  scenario.to_json().stringify(indent=2)
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
