///|
pub(all) struct RuntimeRequest {
  meta : RequestMeta
  body : Bytes
} derive(Eq, Debug)

///|
pub fn RuntimeRequest::new(meta : RequestMeta, body : Bytes) -> RuntimeRequest {
  RuntimeRequest::{ meta, body }
}

///|
pub fn RuntimeRequest::get(uri : String) -> RuntimeRequest {
  RuntimeRequest::{ meta: RequestMeta::simple("GET", uri), body: b"" }
}

///|
pub fn RuntimeRequest::copy(self : RuntimeRequest) -> RuntimeRequest {
  RuntimeRequest::{
    meta: RequestMeta::{ ..self.meta, headers: self.meta.headers.copy() },
    body: self.body,
  }
}

///|
pub(all) struct TransportResponse {
  meta : ResponseMeta
  body : Bytes
} derive(Eq, Debug)

///|
pub fn TransportResponse::new(
  meta : ResponseMeta,
  body : Bytes,
) -> TransportResponse {
  TransportResponse::{ meta, body }
}

///|
pub fn TransportResponse::copy(self : TransportResponse) -> TransportResponse {
  TransportResponse::{
    meta: ResponseMeta::{ ..self.meta, headers: self.meta.headers.copy() },
    body: self.body,
  }
}

///|
pub suberror TransportError {
  ScriptExhausted
  ScriptedTransportFailure(String)
} derive(Eq, Debug)

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
pub(all) enum TransportOutcome {
  TransportSuccess(TransportResponse)
  TransportFailure(String)
} derive(Eq, Debug)

///|
pub struct FakeTransport {
  priv outcomes : Array[TransportOutcome]
  priv mut cursor : Int
}

///|
pub fn FakeTransport::new(
  responses : Array[TransportResponse],
) -> FakeTransport {
  FakeTransport::{
    outcomes: responses.map(fn(response) { TransportSuccess(response) }),
    cursor: 0,
  }
}

///|
pub fn FakeTransport::with_outcomes(
  outcomes : Array[TransportOutcome],
) -> FakeTransport {
  FakeTransport::{ outcomes, cursor: 0 }
}

///|
pub fn FakeTransport::call_count(self : FakeTransport) -> Int {
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
  priv mut cursor : Int
  priv requests : Array[RuntimeRequest]
}

///|
pub fn RecordingTransport::new(
  responses : Array[TransportResponse],
) -> RecordingTransport {
  RecordingTransport::{
    outcomes: responses.map(fn(response) { TransportSuccess(response) }),
    cursor: 0,
    requests: [],
  }
}

///|
pub fn RecordingTransport::with_outcomes(
  outcomes : Array[TransportOutcome],
) -> RecordingTransport {
  RecordingTransport::{ outcomes, cursor: 0, requests: [] }
}

///|
pub fn RecordingTransport::calls(
  self : RecordingTransport,
) -> Array[RuntimeRequest] {
  self.requests.map(fn(request) { request.copy() })
}

///|
pub fn RecordingTransport::call_count(self : RecordingTransport) -> Int {
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
