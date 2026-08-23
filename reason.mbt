///|
/// Stable machine-readable reasons used by policy, store, runtime, and CLI
/// traces. Existing code strings are not repurposed.
pub(all) enum CacheReasonCode {
  StoreAllowed
  StoreMethodUnsupported
  StoreStatusDefault
  StoreStatusExplicit
  StoreStatusUnknown
  StoreNoStore
  StorePrivateShared
  StoreAuthorizationShared
  StoreIncomplete
  StoreVaryStar
  StoreOversized
  StoreCapacityZero
  FreshMaxAge
  FreshSharedMaxAge
  FreshExpires
  FreshHeuristic
  FreshNone
  FreshStillFresh
  FreshStale
  AgeApparent
  AgeCorrected
  AgeClockClamped
  AgeOverflowClamped
  RequestNoStore
  RequestNoCache
  RequestOnlyIfCached
  RequestMaxAge
  RequestMinFresh
  RequestMaxStale
  VaryDefault
  VaryMatched
  VaryMismatch
  VaryMissing
  VaryStar
  RevalidateEtag
  RevalidateLastModified
  RevalidateBoth
  RevalidateCallerCondition
  RevalidateNotModified
  RevalidateModified
  RuntimeHit
  RuntimeMiss
  RuntimeBypass
  RuntimeFetch
  RuntimeStored
  RuntimeNotStored
  RuntimeOnlyIfCachedMiss
  RuntimeCoalesced
  StoreReplaced
  StoreEvictedEntries
  StoreEvictedBytes
  StoreInvalidated
  InvalidateUnsafeMethod
  InvalidateRelatedUri
  InvalidateSkippedSafeMethod
  InvalidateSkippedErrorStatus
} derive(Eq, Compare, Debug)

///|
pub fn CacheReasonCode::code(self : CacheReasonCode) -> String {
  match self {
    StoreAllowed => "MC_STORE_001"
    StoreNoStore => "MC_STORE_002"
    StoreMethodUnsupported => "MC_STORE_003"
    StoreStatusDefault => "MC_STORE_004"
    StoreStatusExplicit => "MC_STORE_005"
    StoreStatusUnknown => "MC_STORE_006"
    StorePrivateShared => "MC_STORE_007"
    StoreAuthorizationShared => "MC_AUTH_001"
    StoreIncomplete => "MC_STORE_008"
    StoreVaryStar => "MC_VARY_004"
    StoreOversized => "MC_STORE_009"
    StoreCapacityZero => "MC_STORE_010"
    FreshMaxAge => "MC_FRESH_001"
    FreshSharedMaxAge => "MC_FRESH_002"
    FreshExpires => "MC_FRESH_003"
    FreshHeuristic => "MC_FRESH_004"
    FreshNone => "MC_FRESH_005"
    FreshStillFresh => "MC_FRESH_006"
    FreshStale => "MC_FRESH_007"
    AgeApparent => "MC_AGE_001"
    AgeCorrected => "MC_AGE_002"
    AgeClockClamped => "MC_AGE_003"
    AgeOverflowClamped => "MC_AGE_004"
    RequestNoStore => "MC_REQ_001"
    RequestNoCache => "MC_REQ_002"
    RequestOnlyIfCached => "MC_REQ_003"
    RequestMaxAge => "MC_REQ_004"
    RequestMinFresh => "MC_REQ_005"
    RequestMaxStale => "MC_REQ_006"
    VaryDefault => "MC_VARY_001"
    VaryMatched => "MC_VARY_002"
    VaryMismatch => "MC_VARY_003"
    VaryMissing => "MC_VARY_005"
    VaryStar => "MC_VARY_006"
    RevalidateEtag => "MC_REVAL_001"
    RevalidateLastModified => "MC_REVAL_002"
    RevalidateBoth => "MC_REVAL_003"
    RevalidateCallerCondition => "MC_REVAL_004"
    RevalidateNotModified => "MC_REVAL_005"
    RevalidateModified => "MC_REVAL_006"
    RuntimeHit => "MC_RUNTIME_001"
    RuntimeMiss => "MC_RUNTIME_002"
    RuntimeBypass => "MC_RUNTIME_003"
    RuntimeFetch => "MC_RUNTIME_004"
    RuntimeStored => "MC_RUNTIME_005"
    RuntimeNotStored => "MC_RUNTIME_006"
    RuntimeOnlyIfCachedMiss => "MC_RUNTIME_007"
    RuntimeCoalesced => "MC_RUNTIME_008"
    StoreReplaced => "MC_MEM_001"
    StoreEvictedEntries => "MC_MEM_002"
    StoreEvictedBytes => "MC_MEM_003"
    StoreInvalidated => "MC_MEM_004"
    InvalidateUnsafeMethod => "MC_INV_001"
    InvalidateRelatedUri => "MC_INV_002"
    InvalidateSkippedSafeMethod => "MC_INV_003"
    InvalidateSkippedErrorStatus => "MC_INV_004"
  }
}

///|
pub fn CacheReasonCode::message(self : CacheReasonCode) -> String {
  match self {
    StoreAllowed => "response is eligible for storage"
    StoreMethodUnsupported => "request method is not cacheable"
    StoreStatusDefault => "status is cacheable by default"
    StoreStatusExplicit => "explicit freshness permits status storage"
    StoreStatusUnknown => "unknown status lacks explicit freshness"
    StoreNoStore => "no-store forbids storage"
    StorePrivateShared => "private response is forbidden in a shared cache"
    StoreAuthorizationShared =>
      "authorized request is not reusable by this shared cache"
    StoreIncomplete => "response body is incomplete"
    StoreVaryStar => "Vary star forbids reuse"
    StoreOversized => "response body exceeds the configured limit"
    StoreCapacityZero => "store capacity is disabled"
    FreshMaxAge => "freshness lifetime comes from max-age"
    FreshSharedMaxAge => "freshness lifetime comes from s-maxage"
    FreshExpires => "freshness lifetime comes from Expires"
    FreshHeuristic => "freshness lifetime is heuristic"
    FreshNone => "response has no freshness lifetime"
    FreshStillFresh => "cached response is fresh"
    FreshStale => "cached response is stale"
    AgeApparent => "apparent age was calculated from Date"
    AgeCorrected => "corrected current age was calculated"
    AgeClockClamped => "backward clock movement was clamped"
    AgeOverflowClamped => "age arithmetic saturated"
    RequestNoStore => "request no-store bypasses cache storage and reuse"
    RequestNoCache => "request no-cache requires validation"
    RequestOnlyIfCached => "request only-if-cached forbids an upstream fetch"
    RequestMaxAge => "request max-age constrains reuse"
    RequestMinFresh => "request min-fresh constrains reuse"
    RequestMaxStale => "request max-stale permits stale reuse"
    VaryDefault => "response has no Vary fields"
    VaryMatched => "all Vary fields matched"
    VaryMismatch => "a Vary field value differed"
    VaryMissing => "a missing Vary field differed from a present field"
    VaryStar => "Vary star has no reusable variant"
    RevalidateEtag => "ETag generated If-None-Match"
    RevalidateLastModified => "Last-Modified generated If-Modified-Since"
    RevalidateBoth => "both validators were added"
    RevalidateCallerCondition => "caller conditional field was preserved"
    RevalidateNotModified => "304 metadata was merged with the cached body"
    RevalidateModified => "upstream returned a replacement response"
    RuntimeHit => "runtime served a cached response"
    RuntimeMiss => "runtime found no matching cache entry"
    RuntimeBypass => "runtime bypassed cache reuse"
    RuntimeFetch => "runtime fetched from the injected transport"
    RuntimeStored => "runtime stored the upstream response"
    RuntimeNotStored => "runtime conservatively skipped storage"
    RuntimeOnlyIfCachedMiss => "only-if-cached request had no reusable response"
    RuntimeCoalesced => "request joined an in-flight cache operation"
    StoreReplaced => "an equal cache variant was replaced"
    StoreEvictedEntries => "entry-count capacity caused deterministic eviction"
    StoreEvictedBytes => "body-byte capacity caused deterministic eviction"
    StoreInvalidated => "all variants for the URI were invalidated"
    InvalidateUnsafeMethod => "successful unsafe method invalidates its target"
    InvalidateRelatedUri => "same-origin related URI is also invalidated"
    InvalidateSkippedSafeMethod =>
      "safe method does not invalidate cache entries"
    InvalidateSkippedErrorStatus => "error response does not invalidate entries"
  }
}

///|
pub(all) struct CacheReason {
  code : CacheReasonCode
  detail : String?
  rfc : String?
} derive(Eq, Debug)

///|
pub fn CacheReason::new(code : CacheReasonCode) -> CacheReason {
  CacheReason::{ code, detail: None, rfc: None }
}

///|
pub fn CacheReason::with_detail(
  code : CacheReasonCode,
  detail : String,
) -> CacheReason {
  CacheReason::{ code, detail: Some(detail), rfc: None }
}

///|
pub fn CacheReason::with_rfc(
  code : CacheReasonCode,
  rfc : String,
) -> CacheReason {
  CacheReason::{ code, detail: None, rfc: Some(rfc) }
}
