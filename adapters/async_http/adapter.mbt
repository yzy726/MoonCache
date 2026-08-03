///|
/// Errors produced by the initial native async adapter.
pub suberror AsyncAdapterError {
  AsyncUnsupportedMethod(String)
  AsyncGetBodyUnsupported
  AsyncRequestCancelled
  AsyncScriptExhausted
  AsyncCoreFailure(String)
  AsyncProbeDidNotRecordRequest
} derive(Eq, Debug)

///|
pub fn AsyncAdapterError::message(self : AsyncAdapterError) -> String {
  match self {
    AsyncUnsupportedMethod(http_method) =>
      "moonbitlang/async/http adapter does not support method \{http_method}"
    AsyncGetBodyUnsupported =>
      "the async HTTP adapter conservatively rejects GET requests with a body"
    AsyncRequestCancelled => "the async HTTP request was cancelled"
    AsyncScriptExhausted => "the async transport script is exhausted"
    AsyncCoreFailure(message) => "cache runtime failed: \{message}"
    AsyncProbeDidNotRecordRequest =>
      "cache runtime requested an origin result without recording a request"
  }
}

///|
/// Async counterpart of the transport-independent core `Transport` trait.
///
/// Keeping this trait in a native-only package prevents the portable policy
/// and runtime packages from depending on an unstable async runtime.
pub(open) trait AsyncTransport {
  async fn execute(Self, @mooncache.RuntimeRequest) -> @mooncache.TransportResponse
}

///|
/// Collapse repeated fields for the current async HTTP client's `Map` API.
///
/// `Host` and `Transfer-Encoding` are omitted because that client generates
/// them itself. All other repeated values use the standard comma convention.
pub fn headers_to_async_http(
  headers : @mooncache.HeaderMap,
) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for name in headers.names() {
    if name != "host" && name != "transfer-encoding" {
      match headers.get(name) {
        Some(value) => result[name] = value
        None => ()
      }
    }
  }
  result
}

///|
/// Convert the async HTTP client's response map to normalized cache headers.
pub fn headers_from_async_http(
  headers : Map[String, String],
) -> @mooncache.HeaderMap {
  let result = @mooncache.HeaderMap::new()
  for name, value in headers {
    ignore(result.append(name, value))
  }
  result
}

///|
/// Minimal native adapter for `moonbitlang/async/http`.
///
/// The injected clock is called after the response body has been received.
/// Callers can use a wall clock in applications and a deterministic clock in
/// tests. The core itself remains free of clock and network dependencies.
pub struct MoonbitAsyncHttpTransport {
  priv response_clock : () -> @mooncache.Timestamp
}

///|
pub fn MoonbitAsyncHttpTransport::new(
  response_clock : () -> @mooncache.Timestamp,
) -> MoonbitAsyncHttpTransport {
  MoonbitAsyncHttpTransport::{ response_clock, }
}

///|
pub fn MoonbitAsyncHttpTransport::fixed(
  response_time : @mooncache.Timestamp,
) -> MoonbitAsyncHttpTransport {
  MoonbitAsyncHttpTransport::{ response_clock: fn() { response_time } }
}

///|
async fn MoonbitAsyncHttpTransport::send(
  self : MoonbitAsyncHttpTransport,
  request : @mooncache.RuntimeRequest,
) -> @mooncache.TransportResponse {
  guard !@async.is_being_cancelled() else { raise AsyncRequestCancelled }
  let headers = headers_to_async_http(request.meta.headers)
  let (response, data) = match request.meta.http_method {
    "GET" => {
      guard request.body.length() == 0 else { raise AsyncGetBodyUnsupported }
      @http.get(request.meta.uri, headers~)
    }
    "POST" => @http.post(request.meta.uri, request.body, headers~)
    "PUT" => @http.put(request.meta.uri, request.body, headers~)
    http_method => raise AsyncUnsupportedMethod(http_method)
  }
  let response_time = (self.response_clock)()
  let meta = @mooncache.ResponseMeta::complete(
    response.code,
    headers_from_async_http(response.headers),
    request.meta.request_time,
    response_time,
  )
  @mooncache.TransportResponse::new(meta, data.binary())
}

///|
pub impl AsyncTransport for MoonbitAsyncHttpTransport with fn execute(
  self,
  request,
) {
  self.send(request)
}

///|
/// Deterministic async origin used by examples and tests.
pub struct ScriptedAsyncTransport {
  priv responses : Array[@mooncache.TransportResponse]
  priv requests : Array[@mooncache.RuntimeRequest]
  priv mut cursor : Int
}

///|
pub fn ScriptedAsyncTransport::new(
  responses : Array[@mooncache.TransportResponse],
) -> ScriptedAsyncTransport {
  ScriptedAsyncTransport::{ responses, requests: [], cursor: 0 }
}

///|
pub fn ScriptedAsyncTransport::call_count(self : ScriptedAsyncTransport) -> Int {
  self.cursor
}

///|
pub fn ScriptedAsyncTransport::calls(
  self : ScriptedAsyncTransport,
) -> Array[@mooncache.RuntimeRequest] {
  self.requests.map(fn(request) { request.copy() })
}

///|
fn ScriptedAsyncTransport::send(
  self : ScriptedAsyncTransport,
  request : @mooncache.RuntimeRequest,
) -> @mooncache.TransportResponse raise AsyncAdapterError {
  self.requests.push(request.copy())
  guard self.cursor < self.responses.length() else {
    raise AsyncScriptExhausted
  }
  let response = self.responses[self.cursor].copy()
  self.cursor = self.cursor + 1
  response
}

///|
pub impl AsyncTransport for ScriptedAsyncTransport with fn execute(
  self,
  request,
) {
  self.send(request)
}

///|
/// Native async wrapper around the portable cache runtime.
///
/// A failing recording transport is first used as a side-effect-free origin
/// probe. Cache hits return immediately. On a miss or revalidation, the exact
/// request selected by the core is sent asynchronously and replayed once into
/// the same core state machine. This avoids maintaining a second copy of RFC
/// policy logic in the adapter.
pub struct AsyncCachedRuntime[S, T] {
  priv store : S
  priv origin : T
  priv options : @mooncache.CacheOptions
}

///|
pub fn[S, T] AsyncCachedRuntime::new(
  store : S,
  origin : T,
  options : @mooncache.CacheOptions,
) -> AsyncCachedRuntime[S, T] {
  AsyncCachedRuntime::{ store, origin, options }
}

///|
pub async fn[S : @mooncache.CacheStore, T : AsyncTransport] AsyncCachedRuntime::execute(
  self : AsyncCachedRuntime[S, T],
  request : @mooncache.RuntimeRequest,
  now : @mooncache.Timestamp,
) -> @mooncache.RuntimeResponse {
  let probe = @mooncache.RecordingTransport::with_outcomes([
    TransportFailure("async origin required"),
  ])
  @mooncache.execute_cached(self.store, probe, self.options, request, now) catch {
    _core_error => {
      guard probe.call_count() == 1 else { raise AsyncProbeDidNotRecordRequest }
      let calls = probe.calls()
      guard calls.length() == 1 else { raise AsyncProbeDidNotRecordRequest }
      let upstream = AsyncTransport::execute(self.origin, calls[0])
      let replay = @mooncache.FakeTransport::new([upstream])
      @mooncache.execute_cached(self.store, replay, self.options, request, now) catch {
        error => raise AsyncCoreFailure(error.message())
      }
    }
  }
}

///|
pub fn[S : @mooncache.CacheStore, T] AsyncCachedRuntime::store_stats(
  self : AsyncCachedRuntime[S, T],
) -> @mooncache.StoreStats {
  @mooncache.CacheStore::stats(self.store)
}
