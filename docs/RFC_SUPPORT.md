# RFC support matrix

This matrix describes the `0.1.2` behavior. “Partial”
means the listed subset is implemented and the omitted part is recorded in
`LIMITATIONS.md`.

| RFC 9111 area | Status | Implementation | Tests / notes |
|---|---|---|---|
| §3 Storing responses | Implemented | `policy_cacheability.mbt`, `MemoryStore::put` | `policy_cacheability_test.mbt`, `memory_store_test.mbt` |
| §3.1 Incomplete responses | Implemented conservatively | `ResponseMeta.body_complete` | incomplete bodies are rejected |
| §3.2 Authorization | Implemented | shared-cache authorization rules | explicit public/s-maxage/must-revalidate cases tested |
| §4 Constructing responses | Implemented for complete GET/HEAD bodies | `runtime_engine.mbt` | HEAD omits the cached body |
| §4.1 Cache key and Vary | Implemented | `variant_uri.mbt`, `variant_vary.mbt` | 18 named Vary tests; missing differs from empty |
| §4.2 Freshness | Implemented | `policy_freshness.mbt`, `policy_decision.mbt` | max-age, s-maxage, Expires, heuristic |
| §4.2.1 Calculating freshness lifetime | Implemented | `calculate_freshness_lifetime` | shared precedence and invalid dates tested |
| §4.2.2 Calculating heuristic freshness | Implemented, configurable | Last-Modified fraction and cap | disabled by default option is testable |
| §4.2.3 Calculating age | Implemented | `policy_age.mbt` | clock rollback and overflow saturation |
| §4.2.4 Serving stale responses | Partial | request `max-stale`, must/proxy-revalidate gates | stale-if-error and background stale serving deferred |
| §4.3 Validation | Implemented | `validation.mbt`, runtime revalidation | ETag, Last-Modified, both, caller conditions |
| §4.3.2 Handling received validation requests | Not applicable | MoonCache is a client/runtime layer | no origin server implementation |
| §4.3.4 Freshening stored responses with 304 | Implemented | `merge_not_modified` | 13 direct 304 tests plus runtime tests |
| §4.4 Invalidation | Implemented for the current scope | `invalidation.mbt` | unsafe target and safe same-origin related URIs |
| §5.2.1 Request Cache-Control | Implemented subset | no-cache, no-store, only-if-cached, max/min-fresh, max-stale | extension tokens ignored |
| §5.2.2 Response Cache-Control | Implemented subset | public, private, no-cache, no-store, max/s-maxage, must/proxy-revalidate | stale extensions parsed; advanced runtime handling deferred |
| §5.3 Expires | Implemented | HTTP-date parser and freshness calculation | invalid/earlier dates are conservative |
| §5.4 Pragma | Implemented for request no-cache compatibility | `request_has_legacy_no_cache` | only used when Cache-Control does not supersede it |
| §5.5 Warning | Not implemented | — | modern cache logic does not synthesize Warning |
| Range / 206 interactions | Not implemented | — | explicitly outside the current scope |

Related RFC 9110 handling:

| Area | Status |
|---|---|
| case-insensitive field names | implemented |
| field-name token validation | implemented |
| end-to-end versus hop-by-hop storage | hop-by-hop response fields stripped |
| safe/unsafe method classification | implemented for runtime invalidation |
| ETag syntax used for validators | conservative validation implemented |

Reason codes identify the exact applied rule. See
[`DECISION_CODES.md`](DECISION_CODES.md).
