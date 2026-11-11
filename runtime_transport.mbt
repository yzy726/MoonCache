///|
#derive(Eq, Debug)
pub(all) struct RuntimeRequest {
  meta : RequestMeta
  body : Bytes
}

///|
pub fn RuntimeRequest::new(meta : RequestMeta, body : Bytes) -> RuntimeRequest {
  { meta, body, }
}

///|
pub fn RuntimeRequest::get(uri : String) -> RuntimeRequest {
  { meta: RequestMeta::simple("GET", uri), body: b"", }
}

///|
pub fn RuntimeRequest::head(uri : String) -> RuntimeRequest {
  { meta: RequestMeta::simple("HEAD", uri), body: b"", }
}

///|
pub fn RuntimeRequest::with_headers(
  self : RuntimeRequest,
  headers : HeaderMap,
) -> RuntimeRequest {
  { meta: self.meta.with_headers(headers), body: self.body, }
}

///|
pub fn RuntimeRequest::with_request_time(
  self : RuntimeRequest,
  request_time : Timestamp,
) -> RuntimeRequest {
  { meta: self.meta.with_request_time(request_time), body: self.body, }
}

///|
pub fn RuntimeRequest::with_body(
  self : RuntimeRequest,
  body : Bytes,
) -> RuntimeRequest {
  { meta: self.meta, body, }
}

///|
pub fn RuntimeRequest::copy(self : RuntimeRequest) -> RuntimeRequest {
  {
    meta: { ..self.meta, headers: self.meta.headers.copy(), },
    body: self.body,
  }
}

///|
#derive(Eq, Debug)
pub(all) struct TransportResponse {
  meta : ResponseMeta
  body : Bytes
}

///|
pub fn TransportResponse::new(
  meta : ResponseMeta,
  body : Bytes,
) -> TransportResponse {
  { meta, body, }
}

///|
pub fn TransportResponse::copy(self : TransportResponse) -> TransportResponse {
  {
    meta: { ..self.meta, headers: self.meta.headers.copy(), },
    body: self.body,
  }
}

///|
#derive(Eq, Debug)
pub suberror TransportError {
  ScriptExhausted
  ScriptedTransportFailure(String)
}

///|
pub fn TransportError::message(self : TransportError) -> String {
  match self {
    ScriptExhausted => "transport script is exhausted"
    ScriptedTransportFailure(message) => message
  }
}

///|
pub(open) trait Transport {
  fn execute(Self, RuntimeRequest) -> TransportResponse raise TransportError
}

///|
#derive(Eq, Debug)
pub(all) enum TransportOutcome {
  TransportSuccess(TransportResponse)
  TransportFailure(String)
}

///|
pub struct FakeTransport {
  priv outcomes : Array[TransportOutcome]
  priv mut cursor : Int32
}

///|
pub fn FakeTransport::new(
  responses : Array[TransportResponse],
) -> FakeTransport {
  {
    outcomes: responses.map(fn(response) { TransportSuccess(response) }),
    cursor: 0,
  }
}

///|
pub fn FakeTransport::with_outcomes(
  outcomes : Array[TransportOutcome],
) -> FakeTransport {
  { outcomes, cursor: 0, }
}

///|
pub fn FakeTransport::call_count(self : FakeTransport) -> Int32 {
  self.cursor
}

///|
pub fn FakeTransport::execute(
  self : FakeTransport,
  _request : RuntimeRequest,
) -> TransportResponse raise TransportError {
  if self.cursor >= self.outcomes.length() {
    raise ScriptExhausted
  }
  let outcome = self.outcomes[self.cursor]
  self.cursor = self.cursor + 1
  match outcome {
    TransportSuccess(response) => response.copy()
    TransportFailure(message) => raise ScriptedTransportFailure(message)
  }
}

///|
pub impl Transport for FakeTransport with fn execute(self, request) {
  FakeTransport::execute(self, request)
}

///|
pub struct RecordingTransport {
  priv outcomes : Array[TransportOutcome]
  priv mut cursor : Int32
  priv requests : Array[RuntimeRequest]
}

///|
pub fn RecordingTransport::new(
  responses : Array[TransportResponse],
) -> RecordingTransport {
  {
    outcomes: responses.map(fn(response) { TransportSuccess(response) }),
    cursor: 0,
    requests: [],
  }
}

///|
pub fn RecordingTransport::with_outcomes(
  outcomes : Array[TransportOutcome],
) -> RecordingTransport {
  { outcomes, cursor: 0, requests: [], }
}

///|
pub fn RecordingTransport::calls(
  self : RecordingTransport,
) -> Array[RuntimeRequest] {
  self.requests.map(fn(request) { request.copy() })
}

///|
pub fn RecordingTransport::call_count(self : RecordingTransport) -> Int32 {
  self.cursor
}

///|
pub fn RecordingTransport::execute(
  self : RecordingTransport,
  request : RuntimeRequest,
) -> TransportResponse raise TransportError {
  self.requests.push(request.copy())
  if self.cursor >= self.outcomes.length() {
    raise ScriptExhausted
  }
  let outcome = self.outcomes[self.cursor]
  self.cursor = self.cursor + 1
  match outcome {
    TransportSuccess(response) => response.copy()
    TransportFailure(message) => raise ScriptedTransportFailure(message)
  }
}

///|
pub impl Transport for RecordingTransport with fn execute(self, request) {
  RecordingTransport::execute(self, request)
}

///|
pub extend RuntimeRequest with @debug.Debug::{to_repr}

///|
pub extend RuntimeRequest with Eq::{not_equal, equal}

///|
pub extend TransportError with @debug.Debug::{to_repr}

///|
pub extend TransportError with Eq::{not_equal, equal}

///|
pub extend TransportOutcome with @debug.Debug::{to_repr}

///|
pub extend TransportOutcome with Eq::{not_equal, equal}

///|
pub extend TransportResponse with @debug.Debug::{to_repr}

///|
pub extend TransportResponse with Eq::{not_equal, equal}
