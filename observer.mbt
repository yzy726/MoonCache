///|
/// Stable operational event categories emitted by cache runtimes.
pub(all) enum CacheEventKind {
  CacheRequestCompleted
  CacheHit
  CacheMiss
  CacheBypass
  CacheStored
  CacheRevalidated
  CacheNotModified
  CacheStaleServed
  CacheUpstreamFetched
  CacheUpstreamError
  CacheEvicted
  CachePurged
  CacheCoalesced
  CacheBytesSaved
  CacheUpstreamRequestSaved
  CacheBackgroundRevalidation
  CacheBackgroundFailure
} derive(Eq, Compare, Debug)

///|
pub fn CacheEventKind::label(self : CacheEventKind) -> String {
  match self {
    CacheRequestCompleted => "REQUEST_COMPLETED"
    CacheHit => "HIT"
    CacheMiss => "MISS"
    CacheBypass => "BYPASS"
    CacheStored => "STORE"
    CacheRevalidated => "REVALIDATE"
    CacheNotModified => "NOT_MODIFIED"
    CacheStaleServed => "STALE_SERVED"
    CacheUpstreamFetched => "UPSTREAM_FETCH"
    CacheUpstreamError => "UPSTREAM_ERROR"
    CacheEvicted => "EVICTION"
    CachePurged => "PURGE"
    CacheCoalesced => "COALESCED"
    CacheBytesSaved => "SAVED_BYTES"
    CacheUpstreamRequestSaved => "SAVED_UPSTREAM_REQUEST"
    CacheBackgroundRevalidation => "BACKGROUND_REVALIDATION"
    CacheBackgroundFailure => "BACKGROUND_FAILURE"
  }
}

///|
/// Privacy-conscious event payload. Headers and response bodies are never
/// included; URI and error detail remain available to an explicitly attached
/// observer and should be redacted by applications when necessary.
pub(all) struct CacheEvent {
  kind : CacheEventKind
  http_method : String
  uri : String
  status : Int?
  body_bytes : Int64
  count : Int64
  duration_milliseconds : Int64
  detail : String?
} derive(Eq, Debug)

///|
pub fn CacheEvent::new(
  kind : CacheEventKind,
  request : RequestMeta,
  status? : Int? = None,
  body_bytes? : Int64 = 0L,
  count? : Int64 = 1L,
  duration_milliseconds? : Int64 = -1L,
  detail? : String? = None,
) -> CacheEvent {
  CacheEvent::{
    kind,
    http_method: request.http_method,
    uri: request.uri,
    status,
    body_bytes: if body_bytes < 0L {
      0L
    } else {
      body_bytes
    },
    count: if count <= 0L {
      1L
    } else {
      count
    },
    duration_milliseconds,
    detail,
  }
}

///|
/// Observer hook for logging, tracing, or application-specific metrics.
pub(open) trait CacheObserver {
  fn observe(Self, CacheEvent) -> Unit
}

///|
pub(all) struct CacheStatsSnapshot {
  requests : Int64
  hits : Int64
  misses : Int64
  bypasses : Int64
  stores : Int64
  revalidations : Int64
  not_modified : Int64
  stale_served : Int64
  upstream_fetches : Int64
  upstream_errors : Int64
  evictions : Int64
  purges : Int64
  purged_entries : Int64
  coalesced_requests : Int64
  saved_bytes : Int64
  saved_upstream_requests : Int64
  validation_samples : Int64
  total_validation_milliseconds : Int64
  average_validation_milliseconds : Int64
  background_revalidations : Int64
  background_failures : Int64
} derive(Eq, Debug)

///|
fn saturated_stats_add(left : Int64, right : Int64) -> Int64 {
  if right <= 0L {
    left
  } else if left >= MAX_DELTA_SECONDS - right {
    MAX_DELTA_SECONDS
  } else {
    left + right
  }
}

///|
fn seconds_to_milliseconds(seconds : Int64) -> Int64 {
  if seconds <= 0L {
    0L
  } else if seconds > MAX_DELTA_SECONDS / 1_000L {
    MAX_DELTA_SECONDS
  } else {
    seconds * 1_000L
  }
}

///|
/// Mutable event accumulator. Call `snapshot` to obtain an immutable report.
pub struct CacheStats {
  priv mut requests : Int64
  priv mut hits : Int64
  priv mut misses : Int64
  priv mut bypasses : Int64
  priv mut stores : Int64
  priv mut revalidations : Int64
  priv mut not_modified : Int64
  priv mut stale_served : Int64
  priv mut upstream_fetches : Int64
  priv mut upstream_errors : Int64
  priv mut evictions : Int64
  priv mut purges : Int64
  priv mut purged_entries : Int64
  priv mut coalesced_requests : Int64
  priv mut saved_bytes : Int64
  priv mut saved_upstream_requests : Int64
  priv mut validation_samples : Int64
  priv mut total_validation_milliseconds : Int64
  priv mut background_revalidations : Int64
  priv mut background_failures : Int64
}

///|
pub fn CacheStats::new() -> CacheStats {
  CacheStats::{
    requests: 0L,
    hits: 0L,
    misses: 0L,
    bypasses: 0L,
    stores: 0L,
    revalidations: 0L,
    not_modified: 0L,
    stale_served: 0L,
    upstream_fetches: 0L,
    upstream_errors: 0L,
    evictions: 0L,
    purges: 0L,
    purged_entries: 0L,
    coalesced_requests: 0L,
    saved_bytes: 0L,
    saved_upstream_requests: 0L,
    validation_samples: 0L,
    total_validation_milliseconds: 0L,
    background_revalidations: 0L,
    background_failures: 0L,
  }
}

///|
fn CacheStats::record(self : CacheStats, event : CacheEvent) -> Unit {
  match event.kind {
    CacheRequestCompleted =>
      self.requests = saturated_stats_add(self.requests, event.count)
    CacheHit => self.hits = saturated_stats_add(self.hits, event.count)
    CacheMiss => self.misses = saturated_stats_add(self.misses, event.count)
    CacheBypass =>
      self.bypasses = saturated_stats_add(self.bypasses, event.count)
    CacheStored => self.stores = saturated_stats_add(self.stores, event.count)
    CacheRevalidated => {
      self.revalidations = saturated_stats_add(self.revalidations, event.count)
      if event.duration_milliseconds >= 0L {
        self.validation_samples = saturated_stats_add(
          self.validation_samples,
          event.count,
        )
        self.total_validation_milliseconds = saturated_stats_add(
          self.total_validation_milliseconds,
          event.duration_milliseconds,
        )
      }
    }
    CacheNotModified =>
      self.not_modified = saturated_stats_add(self.not_modified, event.count)
    CacheStaleServed =>
      self.stale_served = saturated_stats_add(self.stale_served, event.count)
    CacheUpstreamFetched =>
      self.upstream_fetches = saturated_stats_add(
        self.upstream_fetches,
        event.count,
      )
    CacheUpstreamError =>
      self.upstream_errors = saturated_stats_add(
        self.upstream_errors,
        event.count,
      )
    CacheEvicted =>
      self.evictions = saturated_stats_add(self.evictions, event.count)
    CachePurged => {
      self.purges = saturated_stats_add(self.purges, 1L)
      self.purged_entries = saturated_stats_add(
        self.purged_entries,
        event.count,
      )
    }
    CacheCoalesced =>
      self.coalesced_requests = saturated_stats_add(
        self.coalesced_requests,
        event.count,
      )
    CacheBytesSaved =>
      self.saved_bytes = saturated_stats_add(self.saved_bytes, event.body_bytes)
    CacheUpstreamRequestSaved =>
      self.saved_upstream_requests = saturated_stats_add(
        self.saved_upstream_requests,
        event.count,
      )
    CacheBackgroundRevalidation =>
      self.background_revalidations = saturated_stats_add(
        self.background_revalidations,
        event.count,
      )
    CacheBackgroundFailure =>
      self.background_failures = saturated_stats_add(
        self.background_failures,
        event.count,
      )
  }
}

///|
pub impl CacheObserver for CacheStats with fn observe(self, event) {
  self.record(event)
}

///|
pub fn CacheStats::snapshot(self : CacheStats) -> CacheStatsSnapshot {
  CacheStatsSnapshot::{
    requests: self.requests,
    hits: self.hits,
    misses: self.misses,
    bypasses: self.bypasses,
    stores: self.stores,
    revalidations: self.revalidations,
    not_modified: self.not_modified,
    stale_served: self.stale_served,
    upstream_fetches: self.upstream_fetches,
    upstream_errors: self.upstream_errors,
    evictions: self.evictions,
    purges: self.purges,
    purged_entries: self.purged_entries,
    coalesced_requests: self.coalesced_requests,
    saved_bytes: self.saved_bytes,
    saved_upstream_requests: self.saved_upstream_requests,
    validation_samples: self.validation_samples,
    total_validation_milliseconds: self.total_validation_milliseconds,
    average_validation_milliseconds: if self.validation_samples == 0L {
      0L
    } else {
      self.total_validation_milliseconds / self.validation_samples
    },
    background_revalidations: self.background_revalidations,
    background_failures: self.background_failures,
  }
}

///|
/// Reconcile successful observer events with a request group's authoritative
/// count, including followers whose shared operation failed.
pub fn CacheStatsSnapshot::with_coalesced_total(
  self : CacheStatsSnapshot,
  total : Int64,
) -> CacheStatsSnapshot {
  if total <= self.coalesced_requests {
    return self
  }
  let additional = total - self.coalesced_requests
  CacheStatsSnapshot::{
    ..self,
    coalesced_requests: total,
    saved_upstream_requests: saturated_stats_add(
      self.saved_upstream_requests,
      additional,
    ),
  }
}

///|
pub fn CacheStatsSnapshot::hit_rate_per_mille(self : CacheStatsSnapshot) -> Int {
  let classified = saturated_stats_add(
    self.hits,
    saturated_stats_add(self.misses, self.bypasses),
  )
  if classified == 0L {
    0
  } else if self.hits >= classified {
    1_000
  } else {
    (self.hits * 1_000L / classified).to_int()
  }
}

///|
fn telemetry_json_int64(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
pub fn CacheStatsSnapshot::to_json(self : CacheStatsSnapshot) -> Json {
  Json::object({
    "requests": telemetry_json_int64(self.requests),
    "hits": telemetry_json_int64(self.hits),
    "misses": telemetry_json_int64(self.misses),
    "bypasses": telemetry_json_int64(self.bypasses),
    "stores": telemetry_json_int64(self.stores),
    "revalidations": telemetry_json_int64(self.revalidations),
    "not_modified": telemetry_json_int64(self.not_modified),
    "stale_served": telemetry_json_int64(self.stale_served),
    "upstream_fetches": telemetry_json_int64(self.upstream_fetches),
    "upstream_errors": telemetry_json_int64(self.upstream_errors),
    "evictions": telemetry_json_int64(self.evictions),
    "purges": telemetry_json_int64(self.purges),
    "purged_entries": telemetry_json_int64(self.purged_entries),
    "coalesced_requests": telemetry_json_int64(self.coalesced_requests),
    "saved_bytes": telemetry_json_int64(self.saved_bytes),
    "saved_upstream_requests": telemetry_json_int64(
      self.saved_upstream_requests,
    ),
    "validation_samples": telemetry_json_int64(self.validation_samples),
    "total_validation_milliseconds": telemetry_json_int64(
      self.total_validation_milliseconds,
    ),
    "average_validation_milliseconds": telemetry_json_int64(
      self.average_validation_milliseconds,
    ),
    "background_revalidations": telemetry_json_int64(
      self.background_revalidations,
    ),
    "background_failures": telemetry_json_int64(self.background_failures),
    "hit_rate_per_mille": self.hit_rate_per_mille(),
  })
}

///|
pub fn CacheStatsSnapshot::json_report(self : CacheStatsSnapshot) -> String {
  self.to_json().stringify(indent=2)
}

///|
pub fn CacheStatsSnapshot::text_report(self : CacheStatsSnapshot) -> String {
  [
    "Requests: \{self.requests}",
    "Hits: \{self.hits}",
    "Misses: \{self.misses}",
    "Bypasses: \{self.bypasses}",
    "Stores: \{self.stores}",
    "Revalidations: \{self.revalidations}",
    "Not modified: \{self.not_modified}",
    "Stale served: \{self.stale_served}",
    "Upstream fetches: \{self.upstream_fetches}",
    "Upstream errors: \{self.upstream_errors}",
    "Evictions: \{self.evictions}",
    "Purges: \{self.purges} (\{self.purged_entries} entries)",
    "Coalesced requests: \{self.coalesced_requests}",
    "Saved bytes: \{self.saved_bytes}",
    "Saved upstream requests: \{self.saved_upstream_requests}",
    "Average validation: \{self.average_validation_milliseconds}ms",
    "Background revalidations: \{self.background_revalidations}",
    "Background failures: \{self.background_failures}",
  ].join("\n")
}

///|
/// Shared runtime telemetry used by portable and async integrations.
pub struct CacheTelemetry {
  priv stats : CacheStats
  priv observer : ((CacheEvent) -> Unit)?
}

///|
pub fn CacheTelemetry::new() -> CacheTelemetry {
  CacheTelemetry::{ stats: CacheStats::new(), observer: None }
}

///|
pub fn[O : CacheObserver] CacheTelemetry::with_observer(
  self : CacheTelemetry,
  observer : O,
) -> CacheTelemetry {
  CacheTelemetry::{
    ..self,
    observer: Some(fn(event) { CacheObserver::observe(observer, event) }),
  }
}

///|
fn CacheTelemetry::emit(self : CacheTelemetry, event : CacheEvent) -> Unit {
  self.stats.record(event)
  match self.observer {
    Some(observer) => observer(event)
    None => ()
  }
}

///|
fn CacheTelemetry::emit_kind(
  self : CacheTelemetry,
  kind : CacheEventKind,
  request : RequestMeta,
  status? : Int? = None,
  body_bytes? : Int64 = 0L,
  count? : Int64 = 1L,
  duration_milliseconds? : Int64 = -1L,
  detail? : String? = None,
) -> Unit {
  self.emit(
    CacheEvent::new(
      kind,
      request,
      status~,
      body_bytes~,
      count~,
      duration_milliseconds~,
      detail~,
    ),
  )
}

///|
fn CacheTelemetry::record_store_deltas(
  self : CacheTelemetry,
  request : RequestMeta,
  before : StoreStats,
  after : StoreStats,
) -> Unit {
  if after.evictions > before.evictions {
    self.emit_kind(
      CacheEvicted,
      request,
      count=after.evictions - before.evictions,
    )
  }
  if after.invalidated_entries > before.invalidated_entries {
    self.emit_kind(
      CachePurged,
      request,
      count=after.invalidated_entries - before.invalidated_entries,
    )
  }
}

///|
fn response_attempted_origin(response : RuntimeResponse) -> Bool {
  response.source is UpstreamSource ||
  response.source is RevalidatedSource ||
  response.trace.has_reason(StaleIfError)
}

///|
fn response_was_revalidation(response : RuntimeResponse) -> Bool {
  response.trace.has_reason(RevalidateEtag) ||
  response.trace.has_reason(RevalidateLastModified) ||
  response.trace.has_reason(RevalidateBoth)
}

///|
/// Record one non-coalesced runtime result and any Store counter deltas.
pub fn CacheTelemetry::record_response(
  self : CacheTelemetry,
  request : RuntimeRequest,
  response : RuntimeResponse,
  before : StoreStats,
  after : StoreStats,
) -> Unit {
  let status = Some(response.meta.status)
  let body_bytes = response.body.length().to_int64()
  let origin_attempted = response_attempted_origin(response)
  let not_modified = response.trace.has_reason(RevalidateNotModified)
  self.emit_kind(CacheRequestCompleted, request.meta, status~, body_bytes~)
  if response.trace.action is Bypass {
    self.emit_kind(CacheBypass, request.meta, status~)
  }
  if response.trace.has_reason(RuntimeMiss) {
    self.emit_kind(CacheMiss, request.meta, status~)
  }
  if response.source is CacheSource ||
    response.source is StaleSource ||
    not_modified {
    self.emit_kind(CacheHit, request.meta, status~)
  }
  if response.trace.has_reason(RuntimeStored) {
    self.emit_kind(CacheStored, request.meta, status~)
  }
  if response.source is StaleSource {
    self.emit_kind(CacheStaleServed, request.meta, status~, body_bytes~)
  }
  if origin_attempted {
    self.emit_kind(CacheUpstreamFetched, request.meta, status~)
  }
  if response.trace.has_reason(StaleUpstreamError) {
    self.emit_kind(CacheUpstreamError, request.meta, status~)
  }
  if origin_attempted && response_was_revalidation(response) {
    let duration = if response.trace.has_reason(StaleUpstreamError) {
      -1L
    } else {
      seconds_to_milliseconds(
        response.meta.response_time
        .elapsed_since(response.meta.request_time)
        .seconds(),
      )
    }
    self.emit_kind(
      CacheRevalidated,
      request.meta,
      status~,
      duration_milliseconds=duration,
    )
  }
  if not_modified {
    self.emit_kind(CacheNotModified, request.meta, status~)
  }
  let reused_body = response.source is CacheSource ||
    response.source is StaleSource ||
    not_modified
  if reused_body && body_bytes > 0L {
    self.emit_kind(CacheBytesSaved, request.meta, status~, body_bytes~)
  }
  let swr_scheduled = response.trace.has_reason(StaleWhileRevalidate)
  if reused_body && !origin_attempted && !swr_scheduled {
    self.emit_kind(CacheUpstreamRequestSaved, request.meta, status~)
  }
  self.record_store_deltas(request.meta, before, after)
}

///|
pub fn CacheTelemetry::record_upstream_error(
  self : CacheTelemetry,
  request : RuntimeRequest,
  detail : String,
  before : StoreStats,
  after : StoreStats,
) -> Unit {
  self.emit_kind(CacheRequestCompleted, request.meta)
  self.emit_kind(CacheUpstreamFetched, request.meta)
  self.emit_kind(CacheUpstreamError, request.meta, detail=Some(detail))
  self.record_store_deltas(request.meta, before, after)
}

///|
pub fn CacheTelemetry::record_coalesced(
  self : CacheTelemetry,
  request : RuntimeRequest,
  response : RuntimeResponse,
) -> Unit {
  let status = Some(response.meta.status)
  let body_bytes = response.body.length().to_int64()
  self.emit_kind(CacheRequestCompleted, request.meta, status~, body_bytes~)
  self.emit_kind(CacheCoalesced, request.meta, status~)
  self.emit_kind(CacheUpstreamRequestSaved, request.meta, status~)
  if body_bytes > 0L {
    self.emit_kind(CacheBytesSaved, request.meta, status~, body_bytes~)
  }
}

///|
/// Record a coalesced maintenance operation that has no user response body.
pub fn CacheTelemetry::record_coalesced_operation(
  self : CacheTelemetry,
  request : RuntimeRequest,
) -> Unit {
  self.emit_kind(CacheCoalesced, request.meta)
  self.emit_kind(CacheUpstreamRequestSaved, request.meta)
}

///|
pub fn CacheTelemetry::record_background_revalidation(
  self : CacheTelemetry,
  request : RuntimeRequest,
) -> Unit {
  self.emit_kind(CacheBackgroundRevalidation, request.meta)
}

///|
pub fn CacheTelemetry::record_background_failure(
  self : CacheTelemetry,
  request : RuntimeRequest,
  detail : String,
) -> Unit {
  self.emit_kind(CacheBackgroundFailure, request.meta, detail=Some(detail))
}

///|
pub fn CacheTelemetry::record_purge(
  self : CacheTelemetry,
  http_method : String,
  uri : String,
  removed : Int,
) -> Unit {
  if removed <= 0 {
    return
  }
  self.emit_kind(
    CachePurged,
    RequestMeta::simple(http_method, uri),
    count=removed.to_int64(),
  )
}

///|
pub fn CacheTelemetry::snapshot(self : CacheTelemetry) -> CacheStatsSnapshot {
  self.stats.snapshot()
}
