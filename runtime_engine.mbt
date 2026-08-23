///|
pub(all) enum ResponseSource {
  CacheSource
  UpstreamSource
  RevalidatedSource
  StaleSource
  OnlyIfCachedSource
} derive(Eq, Compare, Debug)

///|
pub fn ResponseSource::label(self : ResponseSource) -> String {
  match self {
    CacheSource => "cache"
    UpstreamSource => "upstream"
    RevalidatedSource => "revalidated"
    StaleSource => "stale"
    OnlyIfCachedSource => "only-if-cached"
  }
}

///|
pub(all) struct RuntimeResponse {
  meta : ResponseMeta
  body : Bytes
  source : ResponseSource
  trace : CacheTrace
} derive(Eq, Debug)

///|
/// Deep-copy mutable metadata and trace state while sharing immutable bytes.
pub fn RuntimeResponse::copy(self : RuntimeResponse) -> RuntimeResponse {
  RuntimeResponse::{
    meta: ResponseMeta::{ ..self.meta, headers: self.meta.headers.copy() },
    body: self.body,
    source: self.source,
    trace: self.trace.copy(),
  }
}

///|
pub suberror RuntimeError {
  RuntimeTransportFailure(String)
} derive(Eq, Debug)

///|
pub fn RuntimeError::message(self : RuntimeError) -> String {
  match self {
    RuntimeTransportFailure(message) => message
  }
}

///|
fn[T : Transport] execute_origin(
  transport : T,
  request : RuntimeRequest,
) -> TransportResponse raise RuntimeError {
  Transport::execute(transport, request) catch {
    error => raise RuntimeTransportFailure(error.message())
  }
}

///|
fn cached_meta_with_age(entry : StoredEntry, now : Timestamp) -> ResponseMeta {
  let age = calculate_current_age(entry.response, now)
  let headers = entry.response.headers.copy()
  ignore(headers.set("age", age.current_age.seconds().to_string()))
  // Warning was obsoleted by RFC 9111; never forward a persisted legacy value.
  ignore(headers.remove("warning"))
  ResponseMeta::{ ..entry.response, headers, }
}

///|
fn response_body_for_method(body : Bytes, http_method : String) -> Bytes {
  if http_method == "HEAD" {
    b""
  } else {
    body
  }
}

///|
fn response_from_entry(
  entry : StoredEntry,
  request : RuntimeRequest,
  source : ResponseSource,
  trace : CacheTrace,
  now : Timestamp,
) -> RuntimeResponse {
  RuntimeResponse::{
    meta: cached_meta_with_age(entry, now),
    body: response_body_for_method(entry.body, request.meta.http_method),
    source,
    trace,
  }
}

///|
fn stale_if_error_response(
  entry : StoredEntry,
  request : RuntimeRequest,
  trace : CacheTrace,
  stale_policy : StalePolicy,
  now : Timestamp,
  detail : String,
) -> RuntimeResponse {
  trace.action = ServeStale
  trace.stale_by = Some(stale_policy.stale_by)
  trace.add_reason(CacheReason::with_rfc(StaleIfError, "RFC5861-4"))
  trace.add_reason(CacheReason::with_detail(StaleUpstreamError, detail))
  response_from_entry(entry, request, StaleSource, trace, now)
}

///|
fn record_stale_denial(trace : CacheTrace, policy : StalePolicy) -> Unit {
  if policy.prohibited {
    trace.add_reason(CacheReason::with_rfc(StaleForbidden, "RFC9111-4.2.4"))
  } else if policy.stale_if_error_window is Some(_) {
    trace.add_reason(CacheReason::with_rfc(StaleWindowExceeded, "RFC5861-4"))
  }
}

///|
fn only_if_cached_response(
  request : RuntimeRequest,
  trace : CacheTrace,
  now : Timestamp,
) -> RuntimeResponse {
  let headers = HeaderMap::new()
  ignore(headers.set("content-length", "0"))
  RuntimeResponse::{
    meta: ResponseMeta::complete(504, headers, request.meta.request_time, now),
    body: b"",
    source: OnlyIfCachedSource,
    trace,
  }
}

///|
fn append_reasons(trace : CacheTrace, reasons : Array[CacheReason]) -> Unit {
  for reason in reasons {
    trace.add_reason(reason)
  }
}

///|
fn record_store_result(trace : CacheTrace, result : StorePutResult) -> Unit {
  match result {
    StoreInserted => trace.add_reason(CacheReason::new(RuntimeStored))
    StoreReplacedResult => {
      trace.add_reason(CacheReason::new(StoreReplaced))
      trace.add_reason(CacheReason::new(RuntimeStored))
    }
    StoreRejectedNoStore | StoreRejectedOversized | StoreRejectedCapacity =>
      trace.add_reason(CacheReason::new(RuntimeNotStored))
  }
}

///|
fn[S : CacheStore] store_transport_response(
  store : S,
  request : RuntimeRequest,
  upstream : TransportResponse,
  options : CacheOptions,
  now : Timestamp,
  trace : CacheTrace,
) -> Unit {
  let storage = evaluate_storage(request.meta, upstream.meta, options)
  append_reasons(trace, storage.reasons)
  if !storage.storable {
    trace.add_reason(CacheReason::new(RuntimeNotStored))
    return
  }
  guard primary_cache_key(request.meta) is Some(key) else {
    trace.add_reason(CacheReason::new(RuntimeNotStored))
    return
  }
  let vary = parse_vary(upstream.meta.headers)
  guard build_variant_key(request.meta.headers, vary) is Some(variant) else {
    trace.add_reason(CacheReason::new(RuntimeNotStored))
    return
  }
  let entry = StoredEntry::new(
    key,
    variant,
    request.meta,
    upstream.meta,
    upstream.body,
    storage.policy,
    now,
  )
  record_store_result(trace, CacheStore::put(store, entry))
}

///|
fn[S : CacheStore] apply_invalidation(
  store : S,
  request : RuntimeRequest,
  response : TransportResponse,
  trace : CacheTrace,
) -> Unit {
  let plan = plan_invalidation(request.meta, response.meta)
  append_reasons(trace, plan.reasons)
  for uri in plan.uris {
    let removed = CacheStore::invalidate_uri(store, uri)
    if removed > 0 {
      trace.add_reason(
        CacheReason::with_detail(
          StoreInvalidated,
          "\{removed} entries for \{uri}",
        ),
      )
    }
  }
}

///|
fn[S : CacheStore, T : Transport] fetch_from_origin(
  store : S,
  transport : T,
  request : RuntimeRequest,
  options : CacheOptions,
  now : Timestamp,
  trace : CacheTrace,
  allow_store : Bool,
) -> RuntimeResponse raise RuntimeError {
  if trace.action != Bypass {
    trace.action = Fetch
  }
  trace.add_reason(CacheReason::new(RuntimeFetch))
  let upstream = execute_origin(transport, request)
  if allow_store {
    store_transport_response(store, request, upstream, options, now, trace)
  }
  if !is_safe_http_method(request.meta.http_method) {
    apply_invalidation(store, request, upstream, trace)
  }
  RuntimeResponse::{
    meta: upstream.meta,
    body: response_body_for_method(upstream.body, request.meta.http_method),
    source: UpstreamSource,
    trace,
  }
}

///|
fn[S : CacheStore, T : Transport] execute_revalidation(
  store : S,
  transport : T,
  request : RuntimeRequest,
  entry : StoredEntry,
  options : CacheOptions,
  now : Timestamp,
  trace : CacheTrace,
) -> RuntimeResponse raise RuntimeError {
  let plan = create_revalidation_plan(request.meta, entry.response)
  if !plan.can_revalidate() {
    return fetch_from_origin(
      store, transport, request, options, now, trace, true,
    )
  }
  append_reasons(trace, plan.reasons)
  for pair in plan.generated_headers.pairs() {
    ignore(trace.generated_headers.append(pair.0, pair.1))
  }
  match plan.validator_kind {
    Some(kind) => trace.validator = Some(kind.label())
    None => ()
  }
  let conditional = RuntimeRequest::{ ..request, meta: plan.request }
  let stale_policy = evaluate_stale_policy(
    request.meta,
    entry.response,
    options,
    now,
  )
  let attempt : Result[TransportResponse, RuntimeError] = Ok(
    execute_origin(transport, conditional),
  ) catch {
    error => Err(error)
  }
  let upstream = match attempt {
    Ok(response) => response
    Err(error) => {
      if stale_policy.stale_if_error_allowed {
        return stale_if_error_response(
          entry,
          request,
          trace,
          stale_policy,
          now,
          error.message(),
        )
      }
      record_stale_denial(trace, stale_policy)
      raise error
    }
  }
  if is_stale_if_error_status(upstream.meta.status) {
    if stale_policy.stale_if_error_allowed {
      return stale_if_error_response(
        entry,
        request,
        trace,
        stale_policy,
        now,
        "upstream returned HTTP \{upstream.meta.status}",
      )
    }
    record_stale_denial(trace, stale_policy)
    return RuntimeResponse::{
      meta: upstream.meta,
      body: response_body_for_method(upstream.body, request.meta.http_method),
      source: RevalidatedSource,
      trace,
    }
  }
  if upstream.meta.status == 304 {
    let merged = merge_not_modified(entry, upstream.meta, options, now) catch {
      error => raise RuntimeTransportFailure(error.message())
    }
    append_reasons(trace, merged.reasons)
    if merged.storage.storable {
      record_store_result(trace, CacheStore::put(store, merged.entry))
    } else {
      ignore(
        CacheStore::remove_variant(store, entry.primary_key, entry.variant_key),
      )
    }
    trace.age = Some(calculate_current_age(merged.entry.response, now))
    trace.freshness_lifetime = Some(merged.entry.policy.freshness_lifetime)
    return response_from_entry(
      merged.entry,
      request,
      RevalidatedSource,
      trace,
      now,
    )
  }
  trace.add_reason(CacheReason::new(RevalidateModified))
  ignore(
    CacheStore::remove_variant(store, entry.primary_key, entry.variant_key),
  )
  store_transport_response(store, request, upstream, options, now, trace)
  RuntimeResponse::{
    meta: upstream.meta,
    body: response_body_for_method(upstream.body, request.meta.http_method),
    source: RevalidatedSource,
    trace,
  }
}

///|
/// Execute the complete initial-acceptance cache lifecycle.
pub fn[S : CacheStore, T : Transport] execute_cached(
  store : S,
  transport : T,
  options : CacheOptions,
  request : RuntimeRequest,
  now : Timestamp,
) -> RuntimeResponse raise RuntimeError {
  let request_policy = evaluate_request_policy(request.meta)
  let initial_trace = CacheTrace::new(Fetch)
  if request_policy.bypass {
    initial_trace.action = Bypass
    initial_trace.add_reason(CacheReason::new(RequestNoStore))
    initial_trace.add_reason(CacheReason::new(RuntimeBypass))
    return fetch_from_origin(
      store, transport, request, options, now, initial_trace, false,
    )
  }
  if request.meta.http_method != "GET" && request.meta.http_method != "HEAD" {
    initial_trace.add_reason(CacheReason::new(RuntimeBypass))
    return fetch_from_origin(
      store, transport, request, options, now, initial_trace, false,
    )
  }
  guard primary_cache_key(request.meta) is Some(key) else {
    initial_trace.add_reason(CacheReason::new(RuntimeBypass))
    return fetch_from_origin(
      store, transport, request, options, now, initial_trace, false,
    )
  }
  initial_trace.primary_key = Some(key.label())
  let candidates = CacheStore::find_variants(store, key)
  let selection = select_variant(candidates, request.meta)
  append_reasons(initial_trace, selection.reasons)
  guard selection.entry is Some(entry) else {
    initial_trace.add_reason(CacheReason::new(RuntimeMiss))
    if request_policy.only_if_cached {
      initial_trace.action = OnlyIfCachedMiss
      initial_trace.add_reason(CacheReason::new(RuntimeOnlyIfCachedMiss))
      return only_if_cached_response(request, initial_trace, now)
    }
    return fetch_from_origin(
      store, transport, request, options, now, initial_trace, true,
    )
  }
  initial_trace.selected_variant = Some(entry.variant_key.label)
  let decision = evaluate_cached_response(
    request.meta,
    entry.response,
    options,
    now,
  )
  let trace = decision.trace
  trace.primary_key = Some(key.label())
  trace.selected_variant = Some(entry.variant_key.label)
  append_reasons(trace, selection.reasons)
  match decision.action {
    ServeFresh => response_from_entry(entry, request, CacheSource, trace, now)
    ServeStale => response_from_entry(entry, request, StaleSource, trace, now)
    Revalidate =>
      execute_revalidation(
        store, transport, request, entry, options, now, trace,
      )
    Fetch => {
      trace.add_reason(CacheReason::new(RuntimeFetch))
      let stale_policy = evaluate_stale_policy(
        request.meta,
        entry.response,
        options,
        now,
      )
      let attempt : Result[TransportResponse, RuntimeError] = Ok(
        execute_origin(transport, request),
      ) catch {
        error => Err(error)
      }
      let upstream = match attempt {
        Ok(response) => response
        Err(error) => {
          if stale_policy.stale_if_error_allowed {
            return stale_if_error_response(
              entry,
              request,
              trace,
              stale_policy,
              now,
              error.message(),
            )
          }
          record_stale_denial(trace, stale_policy)
          raise error
        }
      }
      if is_stale_if_error_status(upstream.meta.status) {
        if stale_policy.stale_if_error_allowed {
          return stale_if_error_response(
            entry,
            request,
            trace,
            stale_policy,
            now,
            "upstream returned HTTP \{upstream.meta.status}",
          )
        }
        record_stale_denial(trace, stale_policy)
        return RuntimeResponse::{
          meta: upstream.meta,
          body: response_body_for_method(
            upstream.body,
            request.meta.http_method,
          ),
          source: UpstreamSource,
          trace,
        }
      }
      ignore(
        CacheStore::remove_variant(store, entry.primary_key, entry.variant_key),
      )
      store_transport_response(store, request, upstream, options, now, trace)
      RuntimeResponse::{
        meta: upstream.meta,
        body: response_body_for_method(upstream.body, request.meta.http_method),
        source: UpstreamSource,
        trace,
      }
    }
    Bypass =>
      fetch_from_origin(store, transport, request, options, now, trace, false)
    OnlyIfCachedMiss => only_if_cached_response(request, trace, now)
  }
}

///|
pub struct CachedRuntime[S, T] {
  priv store : S
  priv transport : T
  priv options : CacheOptions
  priv telemetry : CacheTelemetry
}

///|
pub fn[S, T] CachedRuntime::new(
  store : S,
  transport : T,
  options : CacheOptions,
) -> CachedRuntime[S, T] {
  CachedRuntime::{ store, transport, options, telemetry: CacheTelemetry::new() }
}

///|
pub fn[S, T, O : CacheObserver] CachedRuntime::with_observer(
  self : CachedRuntime[S, T],
  observer : O,
) -> CachedRuntime[S, T] {
  CachedRuntime::{ ..self, telemetry: self.telemetry.with_observer(observer) }
}

///|
pub fn[S : CacheStore, T : Transport] CachedRuntime::execute(
  self : CachedRuntime[S, T],
  request : RuntimeRequest,
  now : Timestamp,
) -> RuntimeResponse raise RuntimeError {
  let before = CacheStore::stats(self.store)
  let response = execute_cached(
    self.store,
    self.transport,
    self.options,
    request,
    now,
  ) catch {
    error => {
      let after = CacheStore::stats(self.store)
      self.telemetry.record_upstream_error(
        request,
        error.message(),
        before,
        after,
      )
      raise error
    }
  }
  let after = CacheStore::stats(self.store)
  self.telemetry.record_response(request, response, before, after)
  response
}

///|
pub fn[S : CacheStore, T] CachedRuntime::store_stats(
  self : CachedRuntime[S, T],
) -> StoreStats {
  CacheStore::stats(self.store)
}

///|
pub fn[S, T] CachedRuntime::stats_snapshot(
  self : CachedRuntime[S, T],
) -> CacheStatsSnapshot {
  self.telemetry.snapshot()
}

///|
pub fn[S : CacheStore, T] CachedRuntime::purge(
  self : CachedRuntime[S, T],
  uri : String,
) -> Int {
  let removed = CacheStore::invalidate_uri(self.store, uri)
  self.telemetry.record_purge("PURGE", uri, removed)
  removed
}

///|
pub fn[S : CacheStore, T] CachedRuntime::clear(
  self : CachedRuntime[S, T],
) -> Unit {
  let before = CacheStore::stats(self.store).entries
  CacheStore::clear(self.store)
  self.telemetry.record_purge("CLEAR", "*", before)
}
