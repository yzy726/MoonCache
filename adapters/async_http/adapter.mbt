///|
/// Errors produced by the native async adapter and cached client.
pub suberror AsyncAdapterError {
  AsyncUnsupportedMethod(String)
  AsyncGetBodyUnsupported
  AsyncRequestCancelled
  AsyncInvalidUri(String)
  AsyncBodyTooLarge(actual~ : Int, maximum~ : Int)
  AsyncRequestTimedOut(Int)
  AsyncTooManyRedirects(Int)
  AsyncRedirectRejected(String)
  AsyncScriptExhausted
  AsyncScriptedFailure(String)
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
    AsyncInvalidUri(uri) => "the async HTTP adapter rejected URI \{uri}"
    AsyncBodyTooLarge(actual~, maximum~) =>
      "response body size \{actual} exceeds configured limit \{maximum}"
    AsyncRequestTimedOut(milliseconds) =>
      "the async HTTP request exceeded \{milliseconds}ms"
    AsyncTooManyRedirects(maximum) =>
      "the async cached client exceeded \{maximum} redirects"
    AsyncRedirectRejected(uri) =>
      "the async cached client rejected redirect target \{uri}"
    AsyncScriptExhausted => "the async transport script is exhausted"
    AsyncScriptedFailure(message) => message
    AsyncCoreFailure(message) => "cache runtime failed: \{message}"
    AsyncProbeDidNotRecordRequest =>
      "cache runtime requested an origin result without recording a request"
  }
}

///|
/// Redirect handling is performed above the transport so each followed URI has
/// its own cache key and policy evaluation.
pub(all) enum RedirectPolicy {
  ReturnRedirect
  FollowSameOrigin
  FollowAnyOrigin
} derive(Eq, Compare, Debug)

///|
pub(all) struct CachedClientOptions {
  timeout_milliseconds : Int?
  max_response_body_bytes : Int
  redirect_policy : RedirectPolicy
  max_redirects : Int
  serve_stale_on_timeout : Bool
  enable_stale_while_revalidate : Bool
} derive(Eq, Debug)

///|
pub fn CachedClientOptions::default() -> CachedClientOptions {
  CachedClientOptions::{
    timeout_milliseconds: None,
    max_response_body_bytes: 8 * 1024 * 1024,
    redirect_policy: ReturnRedirect,
    max_redirects: 5,
    serve_stale_on_timeout: false,
    enable_stale_while_revalidate: true,
  }
}

///|
pub fn CachedClientOptions::with_timeout(
  self : CachedClientOptions,
  milliseconds : Int,
) -> CachedClientOptions {
  CachedClientOptions::{
    ..self,
    timeout_milliseconds: if milliseconds > 0 {
      Some(milliseconds)
    } else {
      None
    },
  }
}

///|
pub fn CachedClientOptions::with_body_limit(
  self : CachedClientOptions,
  maximum : Int,
) -> CachedClientOptions {
  CachedClientOptions::{
    ..self,
    max_response_body_bytes: if maximum < 0 {
      0
    } else {
      maximum
    },
  }
}

///|
pub fn CachedClientOptions::with_redirects(
  self : CachedClientOptions,
  policy : RedirectPolicy,
  maximum : Int,
) -> CachedClientOptions {
  CachedClientOptions::{
    ..self,
    redirect_policy: policy,
    max_redirects: if maximum < 0 {
      0
    } else {
      maximum
    },
  }
}

///|
/// Configure whether a client deadline is eligible for stale-if-error.
pub fn CachedClientOptions::with_stale_timeout_fallback(
  self : CachedClientOptions,
  enabled : Bool,
) -> CachedClientOptions {
  CachedClientOptions::{ ..self, serve_stale_on_timeout: enabled }
}

///|
pub fn CachedClientOptions::with_stale_while_revalidate(
  self : CachedClientOptions,
  enabled : Bool,
) -> CachedClientOptions {
  CachedClientOptions::{ ..self, enable_stale_while_revalidate: enabled }
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
fn split_async_uri(uri : String) -> (String, String) raise AsyncAdapterError {
  guard @mooncache.normalize_cache_uri(uri) is Some(normalized) else {
    raise AsyncInvalidUri(uri)
  }
  guard @mooncache.cache_origin(normalized) is Some(origin) else {
    raise AsyncInvalidUri(uri)
  }
  let suffix = normalized[origin.length():].to_owned()
  let target = if suffix == "" {
    "/"
  } else if suffix.has_prefix("?") {
    "/\{suffix}"
  } else {
    suffix
  }
  (origin, target)
}

///|
fn async_request_method(
  http_method : String,
) -> @http.RequestMethod raise AsyncAdapterError {
  match http_method {
    "GET" => Get
    "HEAD" => Head
    "POST" => Post
    "PUT" => Put
    "DELETE" => Delete
    "OPTIONS" => Options
    "PATCH" => Patch
    value => raise AsyncUnsupportedMethod(value)
  }
}

///|
async fn MoonbitAsyncHttpTransport::send(
  self : MoonbitAsyncHttpTransport,
  request : @mooncache.RuntimeRequest,
) -> @mooncache.TransportResponse {
  guard !@async.is_being_cancelled() else { raise AsyncRequestCancelled }
  if request.meta.http_method == "GET" && request.body.length() > 0 {
    raise AsyncGetBodyUnsupported
  }
  if request.meta.http_method == "HEAD" && request.body.length() > 0 {
    raise AsyncGetBodyUnsupported
  }
  let (origin, target) = split_async_uri(request.meta.uri)
  let headers = headers_to_async_http(request.meta.headers)
  let client = @http.Client(origin)
  defer client.close()
  client.request(
    async_request_method(request.meta.http_method),
    target,
    extra_headers=headers,
  )
  if request.body.length() > 0 {
    client.write(request.body)
  }
  let response = client.end_request()
  let body = if request.meta.http_method == "HEAD" {
    client.skip_response_body()
    b""
  } else {
    client.read_all().binary()
  }
  guard !@async.is_being_cancelled() else { raise AsyncRequestCancelled }
  let response_time = (self.response_clock)()
  let meta = @mooncache.ResponseMeta::complete(
    response.code,
    headers_from_async_http(response.headers),
    request.meta.request_time,
    response_time,
  )
  @mooncache.TransportResponse::new(meta, body)
}

///|
pub impl AsyncTransport for MoonbitAsyncHttpTransport with fn execute(
  self,
  request,
) {
  self.send(request)
}

///|
/// Deterministic async origin result used by examples, timeout tests, and
/// network-failure tests.
pub(all) enum AsyncTransportOutcome {
  AsyncTransportSuccess(@mooncache.TransportResponse)
  AsyncTransportFailure(String)
  AsyncTransportDelayed(Int, @mooncache.TransportResponse)
} derive(Eq, Debug)

///|
/// Deterministic async origin used by examples and tests.
pub struct ScriptedAsyncTransport {
  priv outcomes : Array[AsyncTransportOutcome]
  priv requests : Array[@mooncache.RuntimeRequest]
  priv mut cursor : Int
}

///|
pub fn ScriptedAsyncTransport::new(
  responses : Array[@mooncache.TransportResponse],
) -> ScriptedAsyncTransport {
  ScriptedAsyncTransport::{
    outcomes: responses.map(fn(response) { AsyncTransportSuccess(response) }),
    requests: [],
    cursor: 0,
  }
}

///|
pub fn ScriptedAsyncTransport::with_outcomes(
  outcomes : Array[AsyncTransportOutcome],
) -> ScriptedAsyncTransport {
  ScriptedAsyncTransport::{ outcomes, requests: [], cursor: 0 }
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
async fn ScriptedAsyncTransport::send(
  self : ScriptedAsyncTransport,
  request : @mooncache.RuntimeRequest,
) -> @mooncache.TransportResponse {
  self.requests.push(request.copy())
  guard self.cursor < self.outcomes.length() else { raise AsyncScriptExhausted }
  let outcome = self.outcomes[self.cursor]
  self.cursor = self.cursor + 1
  match outcome {
    AsyncTransportSuccess(response) => response.copy()
    AsyncTransportFailure(message) => raise AsyncScriptedFailure(message)
    AsyncTransportDelayed(milliseconds, response) => {
      if milliseconds > 0 {
        @async.sleep(milliseconds)
      }
      response.copy()
    }
  }
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
  priv max_response_body_bytes : Int
}

///|
pub fn[S, T] AsyncCachedRuntime::new(
  store : S,
  origin : T,
  options : @mooncache.CacheOptions,
) -> AsyncCachedRuntime[S, T] {
  AsyncCachedRuntime::{
    store,
    origin,
    options,
    max_response_body_bytes: 8 * 1024 * 1024,
  }
}

///|
pub fn[S, T] AsyncCachedRuntime::with_body_limit(
  self : AsyncCachedRuntime[S, T],
  maximum : Int,
) -> AsyncCachedRuntime[S, T] {
  AsyncCachedRuntime::{
    ..self,
    max_response_body_bytes: if maximum < 0 {
      0
    } else {
      maximum
    },
  }
}

///|
fn replace_stale_error_detail(
  response : @mooncache.RuntimeResponse,
  detail : String,
) -> @mooncache.RuntimeResponse {
  for index = 0; index < response.trace.reasons.length(); index = index + 1 {
    if response.trace.reasons[index].code is StaleUpstreamError {
      response.trace.reasons[index] = @mooncache.CacheReason::with_detail(
        StaleUpstreamError,
        detail,
      )
    }
  }
  response
}

///|
priv enum AsyncStaleUse {
  AsyncStaleIfErrorUse(String)
  AsyncStaleWhileRevalidateUse
}

///|
fn[S : @mooncache.CacheStore, T] AsyncCachedRuntime::stale_candidate(
  self : AsyncCachedRuntime[S, T],
  request : @mooncache.RuntimeRequest,
  now : @mooncache.Timestamp,
  stale_use : AsyncStaleUse,
) -> @mooncache.RuntimeResponse? {
  if (request.meta.http_method != "GET" && request.meta.http_method != "HEAD") ||
    request.body.length() > 0 ||
    request.meta.headers.contains("range") {
    return None
  }
  guard @mooncache.primary_cache_key(request.meta) is Some(key) else {
    return None
  }
  let candidates = @mooncache.CacheStore::find_variants(self.store, key)
  let selection = @mooncache.select_variant(candidates, request.meta)
  guard selection.entry is Some(entry) else { return None }
  let policy = @mooncache.evaluate_stale_policy(
    request.meta,
    entry.response,
    self.options,
    now,
  )
  let allowed = match stale_use {
    AsyncStaleIfErrorUse(_) => policy.stale_if_error_allowed
    AsyncStaleWhileRevalidateUse => policy.stale_while_revalidate_allowed
  }
  guard allowed else { return None }
  let decision = @mooncache.evaluate_cached_response(
    request.meta,
    entry.response,
    self.options,
    now,
  )
  let trace = decision.trace
  trace.action = ServeStale
  trace.stale_by = Some(policy.stale_by)
  trace.primary_key = Some(key.label())
  trace.selected_variant = Some(entry.variant_key.label)
  for reason in selection.reasons {
    trace.add_reason(reason)
  }
  match stale_use {
    AsyncStaleIfErrorUse(detail) => {
      trace.add_reason(
        @mooncache.CacheReason::with_rfc(StaleIfError, "RFC5861-4"),
      )
      trace.add_reason(
        @mooncache.CacheReason::with_detail(StaleUpstreamError, detail),
      )
    }
    AsyncStaleWhileRevalidateUse => {
      trace.add_reason(
        @mooncache.CacheReason::with_rfc(StaleWhileRevalidate, "RFC5861-3"),
      )
      trace.add_reason(@mooncache.CacheReason::new(StaleBackgroundRevalidation))
    }
  }
  let age = @mooncache.calculate_current_age(entry.response, now)
  let headers = entry.response.headers.copy()
  ignore(headers.set("age", age.current_age.seconds().to_string()))
  ignore(headers.remove("warning"))
  Some(@mooncache.RuntimeResponse::{
    meta: @mooncache.ResponseMeta::{ ..entry.response, headers, },
    body: if request.meta.http_method == "HEAD" {
      b""
    } else {
      entry.body
    },
    source: StaleSource,
    trace,
  })
}

///|
pub async fn[S : @mooncache.CacheStore, T : AsyncTransport] AsyncCachedRuntime::execute(
  self : AsyncCachedRuntime[S, T],
  request : @mooncache.RuntimeRequest,
  now : @mooncache.Timestamp,
) -> @mooncache.RuntimeResponse {
  let probe = @mooncache.RecordingTransport::with_outcomes([
    TransportFailure("async origin attempt pending"),
  ])
  let probe_result : Result[@mooncache.RuntimeResponse, Error] = Ok(
    @mooncache.execute_cached(self.store, probe, self.options, request, now),
  ) catch {
    error => Err(error)
  }
  let planned_fallback = match probe_result {
    Ok(response) => {
      if probe.call_count() == 0 {
        return response
      }
      guard probe.call_count() == 1 &&
        response.source is StaleSource &&
        response.trace.has_reason(StaleIfError) else {
        raise AsyncProbeDidNotRecordRequest
      }
      Some(response)
    }
    Err(core_error) => {
      if probe.call_count() == 0 {
        raise AsyncCoreFailure(core_error.to_string())
      }
      guard probe.call_count() == 1 else { raise AsyncProbeDidNotRecordRequest }
      None
    }
  }
  let calls = probe.calls()
  guard calls.length() == 1 else { raise AsyncProbeDidNotRecordRequest }
  let upstream_result : Result[@mooncache.TransportResponse, Error] = Ok(
    AsyncTransport::execute(self.origin, calls[0]),
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => Err(error)
  }
  let upstream = match upstream_result {
    Ok(response) => response
    Err(error) =>
      match planned_fallback {
        Some(response) =>
          return replace_stale_error_detail(response, error.to_string())
        None => raise error
      }
  }
  guard upstream.body.length() <= self.max_response_body_bytes else {
    raise AsyncBodyTooLarge(
      actual=upstream.body.length(),
      maximum=self.max_response_body_bytes,
    )
  }
  let replay = @mooncache.FakeTransport::new([upstream])
  @mooncache.execute_cached(self.store, replay, self.options, request, now) catch {
    error => raise AsyncCoreFailure(error.message())
  }
}

///|
pub fn[S : @mooncache.CacheStore, T] AsyncCachedRuntime::store_stats(
  self : AsyncCachedRuntime[S, T],
) -> @mooncache.StoreStats {
  @mooncache.CacheStore::stats(self.store)
}

///|
fn is_redirect_status(status : Int) -> Bool {
  status == 301 ||
  status == 302 ||
  status == 303 ||
  status == 307 ||
  status == 308
}

///|
fn redirected_method(http_method : String, status : Int) -> String {
  if status == 303 {
    if http_method == "HEAD" {
      "HEAD"
    } else {
      "GET"
    }
  } else if (status == 301 || status == 302) && http_method == "POST" {
    "GET"
  } else {
    http_method
  }
}

///|
fn redirect_request(
  request : @mooncache.RuntimeRequest,
  response : @mooncache.RuntimeResponse,
  policy : RedirectPolicy,
) -> @mooncache.RuntimeRequest? raise AsyncAdapterError {
  if policy is ReturnRedirect || !is_redirect_status(response.meta.status) {
    return None
  }
  guard response.meta.headers.get("location") is Some(location) else {
    return None
  }
  guard @mooncache.resolve_related_uri(request.meta.uri, location)
    is Some(target) else {
    raise AsyncRedirectRejected(location)
  }
  let same_origin = @mooncache.same_cache_origin(request.meta.uri, target)
  if policy is FollowSameOrigin && !same_origin {
    raise AsyncRedirectRejected(target)
  }
  let headers = request.meta.headers.copy()
  if !same_origin {
    ignore(headers.remove("authorization"))
    ignore(headers.remove("proxy-authorization"))
    ignore(headers.remove("cookie"))
  }
  let next_method = redirected_method(
    request.meta.http_method,
    response.meta.status,
  )
  let body = if next_method == request.meta.http_method {
    request.body
  } else {
    ignore(headers.remove("content-length"))
    ignore(headers.remove("content-type"))
    b""
  }
  Some(
    @mooncache.RuntimeRequest::new(
      @mooncache.RequestMeta::new(
        next_method,
        target,
        headers,
        request.meta.request_time,
      ),
      body,
    ),
  )
}

///|
/// High-level native cached HTTP client.
///
/// Redirects are resolved above the cache runtime. Consequently the redirect
/// response and every followed target retain separate cache keys, avoiding
/// accidental aliasing between origins or negotiated resources.
pub struct CachedClient[S, T] {
  priv runtime : AsyncCachedRuntime[S, T]
  priv clock : () -> @mooncache.Timestamp
  priv client_options : CachedClientOptions
  priv request_group : @request_group.RequestGroup[@mooncache.RuntimeResponse]
  priv revalidation_group : @request_group.RequestGroup[Unit]
  priv background_spawn : ((async () -> Unit) -> Unit)?
}

///|
pub fn[S, T] CachedClient::new(
  store : S,
  origin : T,
  cache_options : @mooncache.CacheOptions,
  clock? : () -> @mooncache.Timestamp = fn() { @mooncache.Timestamp::zero() },
  client_options? : CachedClientOptions = CachedClientOptions::default(),
) -> CachedClient[S, T] {
  let runtime = AsyncCachedRuntime::new(store, origin, cache_options).with_body_limit(
    client_options.max_response_body_bytes,
  )
  CachedClient::{
    runtime,
    clock,
    client_options,
    request_group: @request_group.RequestGroup::new(fn(
      response : @mooncache.RuntimeResponse,
    ) {
      response.copy()
    }),
    revalidation_group: @request_group.RequestGroup::new(fn(_unit : Unit) { () }),
    background_spawn: None,
  }
}

///|
/// Attach background revalidation to a caller-owned structured task group.
/// The returned client must not outlive the `with_task_group` scope.
pub fn[S, T, X] CachedClient::with_background_group(
  self : CachedClient[S, T],
  group : @async.TaskGroup[X],
) -> CachedClient[S, T] {
  CachedClient::{
    ..self,
    background_spawn: Some(fn(job) { group.spawn_bg(allow_failure=true, job) }),
  }
}

///|
fn coalescing_component(label : String, value : String) -> String {
  "\{label.length()}:\{label}\{value.length()}:\{value};"
}

///|
/// Hash every representation-affecting request field. This is intentionally
/// conservative: semantically equivalent requests can form separate flights,
/// but distinct Vary candidates can never be merged by omission.
fn request_coalescing_key(request : @mooncache.RuntimeRequest) -> String? {
  let http_method = request.meta.http_method
  if (http_method != "GET" && http_method != "HEAD") ||
    request.body.length() > 0 {
    return None
  }
  let directives = @mooncache.parse_cache_control(
    request.meta.headers.get("cache-control").unwrap_or(""),
  )
  if directives.no_store || request.meta.headers.contains("range") {
    return None
  }
  guard @mooncache.normalize_cache_uri(request.meta.uri) is Some(uri) else {
    return None
  }
  let names = request.meta.headers.names()
  names.sort()
  let mut canonical = coalescing_component("method", http_method) +
    coalescing_component("uri", uri)
  for name in names {
    canonical = canonical + coalescing_component("header", name)
    let values = request.meta.headers.get_all(name)
    canonical = canonical +
      coalescing_component("count", values.length().to_string())
    for value in values {
      canonical = canonical + coalescing_component("value", value)
    }
  }
  Some(@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(canonical))))
}

///|
async fn[S : @mooncache.CacheStore, T : AsyncTransport] CachedClient::execute_once_direct(
  self : CachedClient[S, T],
  request : @mooncache.RuntimeRequest,
  now : @mooncache.Timestamp,
) -> @mooncache.RuntimeResponse {
  try {
    match self.client_options.timeout_milliseconds {
      Some(milliseconds) =>
        @async.with_timeout(
          milliseconds,
          () => self.runtime.execute(request, now),
          error=AsyncRequestTimedOut(milliseconds),
        )
      None => self.runtime.execute(request, now)
    }
  } catch {
    AsyncRequestTimedOut(milliseconds) as error => {
      if self.client_options.serve_stale_on_timeout {
        guard self.runtime.stale_candidate(
            request,
            now,
            AsyncStaleIfErrorUse("client deadline exceeded \{milliseconds}ms"),
          )
          is Some(response) else {
          raise error
        }
        return response
      }
      raise error
    }
    other => raise other
  }
}

///|
fn force_background_revalidation(
  request : @mooncache.RuntimeRequest,
) -> @mooncache.RuntimeRequest {
  let headers = request.meta.headers.copy()
  ignore(headers.set("cache-control", "no-cache"))
  request.copy().with_headers(headers)
}

///|
fn[S : @mooncache.CacheStore, T : AsyncTransport] CachedClient::maybe_serve_stale_while_revalidate(
  self : CachedClient[S, T],
  request : @mooncache.RuntimeRequest,
  now : @mooncache.Timestamp,
) -> @mooncache.RuntimeResponse? {
  guard self.client_options.enable_stale_while_revalidate else { return None }
  guard self.background_spawn is Some(spawn) else { return None }
  guard request_coalescing_key(request) is Some(key) else { return None }
  guard self.runtime.stale_candidate(request, now, AsyncStaleWhileRevalidateUse)
    is Some(response) else {
    return None
  }
  let forced = force_background_revalidation(request)
  spawn(async fn() {
    let background_now = (self.clock)()
    let background_request = forced.with_request_time(background_now)
    ignore(
      self.revalidation_group.run("swr:\{key}", async fn() {
        ignore(self.execute_once_direct(background_request, background_now))
      }),
    ) catch {
      _ => ()
    }
  })
  Some(response)
}

///|
async fn[S : @mooncache.CacheStore, T : AsyncTransport] CachedClient::execute_once(
  self : CachedClient[S, T],
  request : @mooncache.RuntimeRequest,
  now : @mooncache.Timestamp,
) -> @mooncache.RuntimeResponse {
  match self.maybe_serve_stale_while_revalidate(request, now) {
    Some(response) => return response
    None => ()
  }
  match request_coalescing_key(request) {
    None => self.execute_once_direct(request, now)
    Some(key) => {
      let grouped = self.request_group.run(key, () => {
        self.execute_once_direct(request, now)
      })
      let response = grouped.value
      if grouped.coalesced {
        response.trace.add_reason(@mooncache.CacheReason::new(RuntimeCoalesced))
      }
      response
    }
  }
}

///|
pub async fn[S : @mooncache.CacheStore, T : AsyncTransport] CachedClient::execute(
  self : CachedClient[S, T],
  request : @mooncache.RuntimeRequest,
) -> @mooncache.RuntimeResponse {
  let now = (self.clock)()
  let mut current = request.with_request_time(now)
  for redirects = 0; ; redirects = redirects + 1 {
    let response = self.execute_once(current, now)
    guard redirect_request(
        current,
        response,
        self.client_options.redirect_policy,
      )
      is Some(next) else {
      return response
    }
    if redirects >= self.client_options.max_redirects {
      raise AsyncTooManyRedirects(self.client_options.max_redirects)
    }
    current = next
  }
}

///|
pub async fn[S : @mooncache.CacheStore, T : AsyncTransport] CachedClient::get(
  self : CachedClient[S, T],
  uri : String,
  headers? : @mooncache.HeaderMap = @mooncache.HeaderMap::new(),
) -> @mooncache.RuntimeResponse {
  self.execute(@mooncache.RuntimeRequest::get(uri).with_headers(headers))
}

///|
pub async fn[S : @mooncache.CacheStore, T : AsyncTransport] CachedClient::head(
  self : CachedClient[S, T],
  uri : String,
  headers? : @mooncache.HeaderMap = @mooncache.HeaderMap::new(),
) -> @mooncache.RuntimeResponse {
  self.execute(@mooncache.RuntimeRequest::head(uri).with_headers(headers))
}

///|
pub fn[S : @mooncache.CacheStore, T] CachedClient::store_stats(
  self : CachedClient[S, T],
) -> @mooncache.StoreStats {
  self.runtime.store_stats()
}

///|
pub fn[S, T] CachedClient::coalescing_stats(
  self : CachedClient[S, T],
) -> @request_group.RequestGroupStats {
  self.request_group.stats()
}
