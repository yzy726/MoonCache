///|
fn build_storage_family() -> Unit {
  let default_statuses : Array[(Int, String)] = [
    (200, "ok"),
    (203, "non-authoritative"),
    (204, "no-content"),
    (300, "multiple-choices"),
    (301, "moved-permanently"),
    (308, "permanent-redirect"),
    (404, "not-found"),
    (405, "method-not-allowed"),
    (410, "gone"),
    (414, "uri-too-long"),
    (501, "not-implemented"),
  ]
  for i in 0..<default_statuses.length() {
    let entry = default_statuses[i]
    add(
      row(
        "storage",
        "\{entry.1} is default cacheable and fresh",
        "private",
        30,
        "hit",
        reason=Some("MC_FRESH_001"),
        stored_status=Some(entry.0),
        stored_headers=[("Cache-Control", "max-age=60")],
      ),
    )
  }
  let non_default : Array[(Int, String)] = [
    (302, "found"),
    (307, "temporary-redirect"),
    (429, "too-many-requests"),
    (500, "server-error"),
    (403, "forbidden"),
  ]
  for i in 0..<non_default.length() {
    let entry = non_default[i]
    add(
      row(
        "storage",
        "\{entry.1} without explicit expiration is not storable",
        "private",
        10,
        "miss",
        reason=Some("MC_STORE_006"),
        stored_status=Some(entry.0),
        stored_headers=[],
      ),
    )
  }
  add(
    row(
      "storage",
      "206 partial content stays outside the scope",
      "private",
      10,
      "miss",
      reason=Some("MC_STORE_006"),
      stored_status=Some(206),
      stored_headers=[("Cache-Control", "max-age=60")],
    ),
  )
  add(
    row(
      "storage",
      "response no-store forces fetch",
      "private",
      10,
      "fetch",
      reason=Some("MC_STORE_002"),
      stored_headers=[("Cache-Control", "no-store")],
    ),
  )
  add(
    row(
      "storage",
      "request no-store bypasses everything",
      "private",
      10,
      "bypass",
      reason=Some("MC_REQ_001"),
      request_headers=[("Cache-Control", "no-store")],
    ),
  )
  add(
    row(
      "storage",
      "incomplete body is rejected conservatively",
      "private",
      10,
      "fetch",
      reason=Some("MC_STORE_008"),
      complete=false,
    ),
  )
  add(
    row(
      "storage",
      "vary star forbids reuse",
      "private",
      10,
      "fetch",
      reason=Some("MC_VARY_004"),
      stored_headers=[("Cache-Control", "max-age=60"), ("Vary", "*")],
    ),
  )
  add(
    row(
      "storage",
      "explicit public marks 302 storable",
      "shared",
      10,
      "hit",
      reason=Some("MC_FRESH_001"),
      stored_status=Some(302),
      stored_headers=[("Cache-Control", "public, max-age=60")],
    ),
  )
  add(
    row(
      "storage",
      "expires alone makes 302 storable",
      "private",
      10,
      "hit",
      reason=Some("MC_FRESH_003"),
      stored_status=Some(302),
      stored_headers=[("Expires", "Thu, 01 Jan 1970 00:00:40 GMT")],
    ),
  )
  add(
    row(
      "storage",
      "unknown status 599 with explicit expiration stores",
      "private",
      10,
      "hit",
      stored_status=Some(599),
      stored_headers=[("Cache-Control", "max-age=60")],
    ),
  )
  add(
    row(
      "storage",
      "no freshness information still stores but revalidates later",
      "private",
      10,
      "revalidate",
      reason=Some("MC_REVAL_001"),
      stored_headers=[("Cache-Control", "public"), ("ETag", "\"v1\"")],
    ),
  )
}

///|
fn build_freshness_family() -> Unit {
  fresh_boundary_rows("freshness", "max-age 60", 60, "private", [
    ("Cache-Control", "max-age=60"),
  ])
  fresh_boundary_rows("freshness", "max-age 1", 1, "private", [
    ("Cache-Control", "max-age=1"),
  ])
  fresh_boundary_rows("freshness", "s-maxage 90 shared", 90, "shared", [
    ("Cache-Control", "s-maxage=90"),
  ])
  add(
    row(
      "freshness",
      "s-maxage overrides max-age in shared caches",
      "shared",
      70,
      "hit",
      reason=Some("MC_FRESH_002"),
      stored_headers=[("Cache-Control", "max-age=10, s-maxage=120")],
    ),
  )
  add(
    row(
      "freshness",
      "s-maxage ignored by private caches",
      "private",
      20,
      "miss",
      reason=Some("MC_FRESH_007"),
      stored_headers=[("Cache-Control", "max-age=10, s-maxage=120")],
    ),
  )
  add(
    row(
      "freshness",
      "expires lifetime boundary at 41",
      "private",
      41,
      "miss",
      reason=Some("MC_FRESH_007"),
      stored_headers=[
        ("Date", "Thu, 01 Jan 1970 00:00:00 GMT"),
        ("Expires", "Thu, 01 Jan 1970 00:00:40 GMT"),
      ],
    ),
  )
  add(
    row(
      "freshness",
      "unparsable expires degrades to zero lifetime",
      "private",
      1,
      "miss",
      reason=Some("MC_FRESH_003"),
      stored_headers=[("Expires", "not-a-date")],
    ),
  )
  add(
    row(
      "freshness",
      "no freshness source means immediate validation",
      "private",
      0,
      "revalidate",
      reason=Some("MC_REVAL_001"),
      stored_headers=[("ETag", "\"only\"")],
    ),
  )
  add(
    row(
      "freshness",
      "still fresh at half of max-age",
      "private",
      30,
      "hit",
      reason=Some("MC_FRESH_006"),
      stored_headers=[("Cache-Control", "max-age=60")],
    ),
  )
  add(
    row(
      "freshness",
      "zero max-age requires validation every time",
      "private",
      0,
      "revalidate",
      reason=Some("MC_FRESH_001"),
      stored_headers=[("Cache-Control", "max-age=0"), ("ETag", "\"z\"")],
    ),
  )
  add(
    row(
      "freshness",
      "response delay shrinks remaining freshness",
      "private",
      55,
      "hit",
      reason=Some("MC_AGE_002"),
      stored_request_time=0,
      stored_response_time=10,
      stored_headers=[("Cache-Control", "max-age=60")],
    ),
  )
}

///|
fn build_age_family() -> Unit {
  add(
    row(
      "age",
      "date older than response time clamps apparent age",
      "private",
      45,
      "revalidate",
      reason=Some("MC_AGE_003"),
      stored_response_time=0,
      stored_headers=[
        ("Cache-Control", "max-age=30"),
        ("Date", "Thu, 01 Jan 1970 00:00:10 GMT"),
        ("ETag", "\"age-1\""),
      ],
    ),
  )
  add(
    row(
      "age",
      "resident time accumulates after storage",
      "private",
      61,
      "revalidate",
      reason=Some("MC_AGE_002"),
      stored_request_time=0,
      stored_response_time=0,
      stored_headers=[("Cache-Control", "max-age=60"), ("ETag", "\"age-2\"")],
    ),
  )
  add(
    row(
      "age",
      "future date clamps apparent age to zero",
      "private",
      5,
      "hit",
      reason=Some("MC_AGE_003"),
      stored_response_time=0,
      stored_headers=[
        ("Cache-Control", "max-age=60"),
        ("Date", "Thu, 01 Jan 1970 00:10:00 GMT"),
      ],
    ),
  )
  add(
    row(
      "age",
      "century max-age stays fresh without overflow",
      "private",
      1000000,
      "hit",
      reason=Some("MC_FRESH_001"),
      stored_headers=[("Cache-Control", "max-age=3153600000")],
    ),
  )
  for i in 0..<8 {
    let now = [0, 15, 30, 45, 59, 60, 75, 120][i]
    let verdict = if now < 60 {
      ("hit", Some("MC_FRESH_006"))
    } else {
      ("fetch", Some("MC_FRESH_007"))
    }
    add(
      row(
        "age",
        "timeline walk at \{now} seconds",
        "private",
        now,
        verdict.0,
        reason=verdict.1,
      ),
    )
  }
  add(
    row(
      "age",
      "request time after response time keeps age positive",
      "private",
      100,
      "revalidate",
      reason=Some("MC_AGE_002"),
      stored_request_time=5,
      stored_response_time=25,
      stored_headers=[("Cache-Control", "max-age=40"), ("ETag", "\"age-3\"")],
    ),
  )
  add(
    row(
      "age",
      "apparent age plus resident age crosses lifetime together",
      "private",
      80,
      "revalidate",
      reason=Some("MC_AGE_002"),
      stored_response_time=0,
      stored_headers=[
        ("Cache-Control", "max-age=60"),
        ("Date", "Thu, 01 Jan 1970 00:00:30 GMT"),
        ("ETag", "\"age-4\""),
      ],
    ),
  )
  add(
    row(
      "age",
      "clock clamp keeps fresh decision stable",
      "private",
      59,
      "hit",
      reason=Some("MC_AGE_003"),
      stored_response_time=0,
      stored_headers=[
        ("Cache-Control", "max-age=60"),
        ("Date", "Thu, 01 Jan 1970 00:05:00 GMT"),
      ],
    ),
  )
  add(
    row(
      "age",
      "overflow clamp on absurd expires gap",
      "private",
      1000000,
      "hit",
      reason=Some("MC_FRESH_003"),
      stored_headers=[("Expires", "Fri, 01 Jan 9999 00:00:00 GMT")],
    ),
  )
  add(
    row(
      "age",
      "negative offset cannot produce negative age",
      "private",
      3,
      "hit",
      reason=Some("MC_AGE_003"),
      stored_response_time=10,
      stored_headers=[("Cache-Control", "max-age=60")],
    ),
  )
}

///|
fn build_request_family() -> Unit {
  add(
    row(
      "request",
      "request no-cache forces revalidation despite freshness",
      "private",
      5,
      "revalidate",
      reason=Some("MC_REQ_002"),
      request_headers=[("Cache-Control", "no-cache")],
      stored_headers=[("Cache-Control", "max-age=60"), ("ETag", "\"rq-1\"")],
    ),
  )
  add(
    row(
      "request",
      "request no-cache on stale entry without validator fetches",
      "private",
      120,
      "fetch",
      reason=Some("MC_REQ_002"),
      request_headers=[("Cache-Control", "no-cache")],
      stored_headers=[("Cache-Control", "max-age=60")],
    ),
  )
  add(
    row(
      "request",
      "only-if-cached serves fresh entry",
      "private",
      10,
      "hit",
      reason=Some("MC_RUNTIME_001"),
      request_headers=[("Cache-Control", "only-if-cached")],
    ),
  )
  add(
    row(
      "request",
      "only-if-cached misses when nothing stored",
      "private",
      10,
      "only_if_cached_miss",
      reason=Some("MC_REQ_003"),
      request_headers=[("Cache-Control", "only-if-cached")],
      stored_status=None,
    ),
  )
  add(
    row(
      "request",
      "only-if-cached refuses stale beyond max-stale window",
      "private",
      120,
      "only_if_cached_miss",
      reason=Some("MC_RUNTIME_007"),
      request_headers=[("Cache-Control", "only-if-cached")],
    ),
  )
  add(
    row(
      "request",
      "request max-age shrinks usable freshness",
      "private",
      30,
      "miss",
      reason=Some("MC_REQ_004"),
      request_headers=[("Cache-Control", "max-age=20")],
    ),
  )
  add(
    row(
      "request",
      "request max-age above response lifetime keeps hit",
      "private",
      30,
      "hit",
      reason=Some("MC_FRESH_006"),
      request_headers=[("Cache-Control", "max-age=600")],
    ),
  )
  add(
    row(
      "request",
      "min-fresh guards the boundary from below",
      "private",
      50,
      "miss",
      reason=Some("MC_REQ_005"),
      request_headers=[("Cache-Control", "min-fresh=15")],
    ),
  )
  add(
    row(
      "request",
      "min-fresh satisfied early enough",
      "private",
      40,
      "hit",
      reason=Some("MC_FRESH_006"),
      request_headers=[("Cache-Control", "min-fresh=15")],
    ),
  )
  add(
    row(
      "request",
      "max-stale permits limited staleness",
      "private",
      80,
      "stale",
      reason=Some("MC_REQ_006"),
      request_headers=[("Cache-Control", "max-stale=30")],
    ),
  )
  add(
    row(
      "request",
      "max-stale beyond window revalidates instead",
      "private",
      130,
      "revalidate",
      reason=Some("MC_REVAL_001"),
      request_headers=[("Cache-Control", "max-stale=30")],
      stored_headers=[("Cache-Control", "max-age=60"), ("ETag", "\"rq-2\"")],
    ),
  )
  add(
    row(
      "request",
      "unbounded max-stale serves any staleness",
      "private",
      500,
      "stale",
      reason=Some("MC_REQ_006"),
      request_headers=[("Cache-Control", "max-stale")],
    ),
  )
  add(
    row(
      "request",
      "max-stale yields to must-revalidate",
      "private",
      80,
      "revalidate",
      reason=Some("MC_REVAL_001"),
      request_headers=[("Cache-Control", "max-stale=30")],
      stored_headers=[
        ("Cache-Control", "max-age=60, must-revalidate"),
        ("ETag", "\"m\""),
      ],
    ),
  )
  add(
    row(
      "request",
      "max-stale yields to response no-cache",
      "private",
      80,
      "revalidate",
      reason=Some("MC_FRESH_007"),
      request_headers=[("Cache-Control", "max-stale=30")],
      stored_headers=[
        ("Cache-Control", "max-age=60, no-cache"),
        ("ETag", "\"n\""),
      ],
    ),
  )
  add(
    row(
      "request",
      "combined directives evaluate together",
      "private",
      30,
      "hit",
      reason=Some("MC_FRESH_006"),
      request_headers=[
        ("Cache-Control", "min-fresh=5, max-stale=10, max-age=100"),
      ],
    ),
  )
  add(
    row(
      "request",
      "legacy pragma no-cache forces revalidation",
      "private",
      5,
      "revalidate",
      reason=Some("MC_REQ_002"),
      request_headers=[("Pragma", "no-cache")],
      stored_headers=[("Cache-Control", "max-age=60"), ("ETag", "\"pg\"")],
    ),
  )
}

///|
fn build_validation_family() -> Unit {
  add(
    row(
      "validation",
      "stale strong etag revalidates",
      "private",
      90,
      "revalidate",
      reason=Some("MC_REVAL_001"),
      stored_headers=[("Cache-Control", "max-age=60"), ("ETag", "\"asset-v3\"")],
    ),
  )
  add(
    row(
      "validation",
      "weak etag still validates",
      "private",
      90,
      "revalidate",
      reason=Some("MC_REVAL_001"),
      stored_headers=[("Cache-Control", "max-age=60"), ("ETag", "W/\"soft\"")],
    ),
  )
  add(
    row(
      "validation",
      "last-modified alone revalidates",
      "private",
      90,
      "revalidate",
      reason=Some("MC_REVAL_001"),
      stored_headers=[
        ("Cache-Control", "max-age=60"),
        ("Last-Modified", "Thu, 01 Jan 1970 00:00:10 GMT"),
      ],
    ),
  )
  add(
    row(
      "validation",
      "etag takes precedence reporting both present",
      "private",
      90,
      "revalidate",
      reason=Some("MC_REVAL_001"),
      stored_headers=[
        ("Cache-Control", "max-age=60"),
        ("ETag", "\"both\""),
        ("Last-Modified", "Thu, 01 Jan 1970 00:00:10 GMT"),
      ],
    ),
  )
  add(
    row(
      "validation",
      "stale without validator performs plain fetch",
      "private",
      90,
      "fetch",
      reason=Some("MC_RUNTIME_004"),
    ),
  )
  add(
    row(
      "validation",
      "fresh no-cache response revalidates with etag",
      "private",
      1,
      "revalidate",
      reason=Some("MC_REVAL_001"),
      stored_headers=[
        ("Cache-Control", "max-age=60, no-cache"),
        ("ETag", "\"nc\""),
      ],
    ),
  )
  add(
    row(
      "validation",
      "caller conditional headers are preserved for revalidation",
      "private",
      90,
      "revalidate",
      reason=Some("MC_REVAL_001"),
      request_headers=[("If-None-Match", "\"caller-v\"")],
      stored_headers=[("Cache-Control", "max-age=60"), ("ETag", "\"stored-v\"")],
    ),
  )
  for i in 0..<12 {
    let etags = [
      "\"a\"", "\"b\"", "W/\"c\"", "\"d\"", "\"e\"", "\"f\"", "\"g\"", "\"h\"", "W/\"i\"",
      "\"j\"", "\"k\"", "\"l\"",
    ]
    add(
      row(
        "validation",
        "etag matrix case \{i + 1} revalidates when stale",
        "private",
        61 + i,
        "revalidate",
        reason=Some("MC_REVAL_001"),
        stored_headers=[("Cache-Control", "max-age=60"), ("ETag", etags[i])],
      ),
    )
  }
  for i in 0..<12 {
    let ages = 61 + i * 5
    add(
      row(
        "validation",
        "last-modified matrix case \{i + 1} at \{ages}",
        "private",
        ages,
        "revalidate",
        reason=Some("MC_REVAL_001"),
        stored_headers=[
          ("Cache-Control", "max-age=60"),
          ("Last-Modified", "Thu, 01 Jan 1970 00:01:00 GMT"),
        ],
      ),
    )
  }
}

///|
fn build_vary_family() -> Unit {
  let vary_specs : Array[String] = [
    "Accept-Language", "accept-language", "ACCEPT-LANGUAGE", "User-Agent", "Accept-Encoding, User-Agent",
    "Accept, Accept-Language", "X-Custom", "Accept-Language, X-Custom, User-Agent",
  ]
  for i in 0..<vary_specs.length() {
    let spec = vary_specs[i]
    add(
      row(
        "vary",
        "single header varies on \{spec}",
        "private",
        10,
        "hit",
        reason=None,
        request_headers=[(header_name_of(i), "value-\{i}")],
        stored_headers=[("Cache-Control", "max-age=60"), ("Vary", spec)],
      ),
    )
  }
  add(
    row(
      "vary",
      "default variant matches empty vary list",
      "private",
      10,
      "hit",
      reason=None,
    ),
  )
  add(
    row(
      "vary",
      "missing request field selects missing variant",
      "private",
      10,
      "hit",
      reason=None,
      stored_headers=[
        ("Cache-Control", "max-age=60"),
        ("Vary", "Accept-Language"),
      ],
    ),
  )
  add(
    row(
      "vary",
      "empty request value differs from missing value",
      "private",
      10,
      "hit",
      reason=None,
      request_headers=[("Accept-Language", "")],
      stored_headers=[
        ("Cache-Control", "max-age=60"),
        ("Vary", "Accept-Language"),
      ],
    ),
  )
  add(
    row(
      "vary",
      "case differences in values change variants not matching",
      "private",
      10,
      "hit",
      reason=None,
      request_headers=[("Accept-Language", "EN")],
      stored_headers=[
        ("Cache-Control", "max-age=60"),
        ("Vary", "Accept-Language"),
      ],
    ),
  )
  add(
    row(
      "vary",
      "multi field order does not affect selection label",
      "private",
      10,
      "hit",
      reason=None,
      request_headers=[("User-Agent", "agent/1"), ("Accept", "text/html")],
      stored_headers=[
        ("Cache-Control", "max-age=60"),
        ("Vary", "user-agent, accept"),
      ],
    ),
  )
}

///|
fn header_name_of(index : Int) -> String {
  let names = [
    "Accept-Language", "User-Agent", "Accept-Encoding", "Accept", "X-Custom", "Referer",
    "X-Device", "X-Region",
  ]
  names[index % names.length()]
}

///|
fn build_shared_family() -> Unit {
  add(
    row(
      "shared",
      "private response cannot enter shared cache",
      "shared",
      10,
      "fetch",
      reason=Some("MC_STORE_007"),
      stored_headers=[("Cache-Control", "private, max-age=60")],
    ),
  )
  add(
    row(
      "shared",
      "private response is fine for private caches",
      "private",
      10,
      "hit",
      reason=Some("MC_FRESH_001"),
      stored_headers=[("Cache-Control", "private, max-age=60")],
    ),
  )
  add(
    row(
      "shared",
      "proxy-revalidate blocks shared stale reuse",
      "shared",
      90,
      "revalidate",
      reason=Some("MC_REVAL_001"),
      stored_headers=[
        ("Cache-Control", "max-age=60, proxy-revalidate"),
        ("ETag", "\"p\""),
      ],
    ),
  )
  add(
    row(
      "shared",
      "proxy-revalidate irrelevant to private caches",
      "private",
      80,
      "miss",
      reason=Some("MC_FRESH_007"),
      stored_headers=[("Cache-Control", "max-age=60, proxy-revalidate")],
    ),
  )
  add(
    row(
      "shared",
      "s-maxage preferred over max-age when shared",
      "shared",
      100,
      "hit",
      reason=Some("MC_FRESH_002"),
      stored_headers=[("Cache-Control", "max-age=30, s-maxage=300")],
    ),
  )
  add(
    row(
      "shared",
      "must-revalidate forbids stale serving in shared too",
      "shared",
      70,
      "revalidate",
      reason=Some("MC_REVAL_001"),
      request_headers=[("Cache-Control", "max-stale=60")],
      stored_headers=[
        ("Cache-Control", "max-age=60, must-revalidate"),
        ("ETag", "\"mr\""),
      ],
    ),
  )
  for i in 0..<18 {
    let modes = ["shared", "private"]
    let mode = modes[i % 2]
    let lifetimes = 30 + i * 10
    let now = if i < 9 { lifetimes - 1 } else { lifetimes + 5 }
    let verdict = if now < lifetimes {
      ("hit", Some("MC_FRESH_006"))
    } else {
      ("fetch", Some("MC_FRESH_007"))
    }
    add(
      row(
        "shared",
        "mode matrix \{i + 1} \{mode} lifetime \{lifetimes}",
        mode,
        now,
        verdict.0,
        reason=verdict.1,
        stored_headers=[("Cache-Control", "max-age=\{lifetimes}")],
      ),
    )
  }
}

///|
fn build_authorization_family() -> Unit {
  add(
    row(
      "authorization",
      "authorized request bypasses shared cache by default",
      "shared",
      10,
      "fetch",
      reason=Some("MC_AUTH_001"),
      request_headers=[("Authorization", "Bearer zzz")],
    ),
  )
  add(
    row(
      "authorization",
      "public response may serve authorized requests in shared cache",
      "shared",
      10,
      "hit",
      reason=Some("MC_FRESH_001"),
      request_headers=[("Authorization", "Bearer zzz")],
      stored_headers=[("Cache-Control", "public, max-age=60")],
    ),
  )
  add(
    row(
      "authorization",
      "s-maxage authorizes shared storage too",
      "shared",
      10,
      "hit",
      reason=Some("MC_FRESH_002"),
      request_headers=[("Authorization", "Bearer zzz")],
      stored_headers=[("Cache-Control", "s-maxage=60")],
    ),
  )
  add(
    row(
      "authorization",
      "must-revalidate authorizes shared storage",
      "shared",
      10,
      "hit",
      reason=Some("MC_FRESH_001"),
      request_headers=[("Authorization", "Bearer zzz")],
      stored_headers=[("Cache-Control", "max-age=60, must-revalidate")],
    ),
  )
  add(
    row(
      "authorization",
      "authorization is harmless for private caches",
      "private",
      10,
      "hit",
      reason=Some("MC_FRESH_001"),
      request_headers=[("Authorization", "Bearer zzz")],
    ),
  )
  add(
    row(
      "authorization",
      "stale authorized shared entry revalidates",
      "shared",
      90,
      "revalidate",
      reason=Some("MC_REVAL_001"),
      request_headers=[("Authorization", "Bearer zzz")],
      stored_headers=[
        ("Cache-Control", "public, max-age=60"),
        ("ETag", "\"auth-1\""),
      ],
    ),
  )
  for i in 0..<8 {
    let tokens = ["aaa", "bbb", "ccc", "ddd", "eee", "fff", "ggg", "hhh"]
    add(
      row(
        "authorization",
        "token matrix \{tokens[i]} stays private",
        "shared",
        10 + i,
        "fetch",
        reason=Some("MC_AUTH_001"),
        request_headers=[("Authorization", "Bearer \{tokens[i]}")],
      ),
    )
  }
}

///|
fn build_method_family() -> Unit {
  add(
    row(
      "method",
      "head responses are cacheable by default",
      "private",
      10,
      "hit",
      reason=Some("MC_FRESH_001"),
      http_method="HEAD",
    ),
  )
  add(
    row(
      "method",
      "post never reads from cache policy layer",
      "private",
      10,
      "fetch",
      reason=None,
      http_method="POST",
      stored_status=None,
    ),
  )
  add(
    row(
      "method",
      "put requests do not consult cached entries",
      "private",
      10,
      "fetch",
      reason=None,
      http_method="PUT",
      stored_status=None,
    ),
  )
  add(
    row(
      "method",
      "delete requests are unsupported for storage",
      "private",
      10,
      "fetch",
      reason=None,
      http_method="DELETE",
      stored_status=None,
    ),
  )
  for i in 0..<8 {
    let methods = ["HEAD", "GET", "HEAD", "GET", "HEAD", "GET", "HEAD", "GET"]
    add(
      row(
        "method",
        "alternating matrix \{i + 1} uses \{methods[i]}",
        "private",
        10 + i,
        "hit",
        reason=Some("MC_FRESH_006"),
        http_method=methods[i],
      ),
    )
  }
}

///|
fn build_heuristic_family() -> Unit {
  let resource_age_seconds = [3600, 86400, 604800, 2592000]
  for i in 0..<resource_age_seconds.length() {
    let age = resource_age_seconds[i]
    let raw_lifetime = age / 10
    let lifetime = if raw_lifetime > 86_400 { 86_400 } else { raw_lifetime }
    add(
      row(
        "heuristic",
        "heuristic ten percent of \{age} seconds",
        "private",
        lifetime - 1,
        "hit",
        reason=Some("MC_FRESH_004"),
        stored_headers=[
          ("Date", format_post_epoch(age)),
          ("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT"),
        ],
      ),
    )
  }
  add(
    row(
      "heuristic",
      "heuristic cap limits very old resources",
      "private",
      86_400,
      "revalidate",
      reason=Some("MC_FRESH_004"),
      stored_headers=[
        ("Date", format_post_epoch(100_000_000)),
        ("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT"),
      ],
    ),
  )
  add(
    row(
      "heuristic",
      "explicit max-age beats heuristic",
      "private",
      30,
      "hit",
      reason=Some("MC_FRESH_001"),
      stored_headers=[
        ("Cache-Control", "max-age=60"),
        ("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT"),
      ],
    ),
  )
  add(
    row(
      "heuristic",
      "expires beats heuristic",
      "private",
      30,
      "hit",
      reason=Some("MC_FRESH_003"),
      stored_headers=[
        ("Expires", "Thu, 01 Jan 1970 00:01:00 GMT"),
        ("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT"),
      ],
    ),
  )
  for i in 0..<12 {
    let now = 5 + i * 10
    add(
      row(
        "heuristic",
        "heuristic timeline \{i + 1} at \{now}",
        "private",
        now,
        "hit",
        reason=Some("MC_FRESH_004"),
        stored_headers=[
          ("Date", "Thu, 01 Jan 1970 01:00:00 GMT"),
          ("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT"),
        ],
      ),
    )
  }
}

///|
fn format_post_epoch(total_seconds : Int) -> String {
  // Minimal RFC1123 formatter for the fixture epoch range.
  let days = total_seconds / 86400
  let rem = total_seconds % 86400
  let hour = rem / 3600
  let minute = rem % 3600 / 60
  let second = rem % 60
  let weekdays = ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"]
  let weekday = weekdays[days % 7]
  "\{weekday}, \{pad2(days + 1)} Jan 1970 \{pad2(hour)}:\{pad2(minute)}:\{pad2(second)} GMT"
}

///|
fn pad2(value : Int) -> String {
  if value < 10 {
    "0\{value}"
  } else {
    "\{value}"
  }
}
