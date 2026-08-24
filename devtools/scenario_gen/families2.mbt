///|
fn build_boundary_matrix_family() -> Unit {
  let lifetimes : Array[Int] = [30, 120, 300, 1800, 3600]
  for i in 0..<lifetimes.length() {
    fresh_boundary_rows(
      "matrix",
      "max-age \{lifetimes[i]}",
      lifetimes[i],
      "private",
      [("Cache-Control", "max-age=\{lifetimes[i]}")],
    )
  }
  let s_maxage_cases : Array[(Int, Int)] = [
    (60, 59),
    (60, 60),
    (60, 90),
    (200, 199),
    (200, 260),
  ]
  for i in 0..<s_maxage_cases.length() {
    let lifetime = s_maxage_cases[i].0
    let now = s_maxage_cases[i].1
    add(
      row(
        "matrix",
        "shared s-maxage \{lifetime} at \{now}",
        "shared",
        now,
        if now < lifetime {
          "hit"
        } else {
          "fetch"
        },
        reason=if now < lifetime {
          Some("MC_FRESH_002")
        } else {
          Some("MC_FRESH_007")
        },
        stored_headers=[("Cache-Control", "s-maxage=\{lifetime}")],
      ),
    )
  }
}

///|
fn build_request_matrix_family() -> Unit {
  for i in 0..<12 {
    let max_age_req = 10 + i * 5
    let verdict = if max_age_req > 40 { "hit" } else { "fetch" }
    add(
      row(
        "request",
        "max-age ladder \{max_age_req} against lifetime 60",
        "private",
        40,
        verdict,
        reason=if verdict == "hit" {
          Some("MC_FRESH_006")
        } else {
          Some("MC_REQ_004")
        },
        request_headers=[("Cache-Control", "max-age=\{max_age_req}")],
      ),
    )
  }
  for i in 0..<9 {
    let window = i * 10
    let stale_by = 20
    let now = 80
    let verdict = if window >= stale_by { "stale" } else { "revalidate" }
    add(
      row(
        "request",
        "max-stale window \{window} versus staleness \{stale_by}",
        "private",
        now,
        verdict,
        reason=if verdict == "stale" {
          Some("MC_REQ_006")
        } else {
          Some("MC_REVAL_001")
        },
        request_headers=[("Cache-Control", "max-stale=\{window}")],
        stored_headers=[("Cache-Control", "max-age=60"), ("ETag", "\"ms\"")],
      ),
    )
  }
  for i in 0..<9 {
    let margin = i * 5
    let now = 45
    let verdict = if now + margin < 60 { "hit" } else { "fetch" }
    add(
      row(
        "request",
        "min-fresh margin \{margin} at age \{now}",
        "private",
        now,
        verdict,
        reason=if verdict == "hit" {
          Some("MC_FRESH_006")
        } else {
          Some("MC_REQ_005")
        },
        request_headers=[("Cache-Control", "min-fresh=\{margin}")],
      ),
    )
  }
}

///|
fn build_storage_mode_matrix_family() -> Unit {
  let statuses : Array[Int] = [
    200, 203, 204, 206, 301, 302, 308, 404, 410, 501, 504,
  ]
  for i in 0..<statuses.length() {
    let status = statuses[i]
    add(
      row(
        "storage",
        "status \{status} in shared mode without expiration",
        "shared",
        10,
        if status == 206 {
          "miss"
        } else {
          "hit"
        },
        reason=Some(if status == 206 { "MC_STORE_006" } else { "MC_FRESH_002" }),
        stored_status=Some(status),
        stored_headers=[("Cache-Control", "s-maxage=60")],
      ),
    )
  }
}

///|
fn build_validation_extra_family() -> Unit {
  for i in 0..<10 {
    let validators : Array[(String, String)] = [
      ("ETag", "\"x\{i}\""),
      ("Last-Modified", "Thu, 01 Jan 1970 00:00:\{pad2(i)} GMT"),
    ]
    let reason = "MC_REVAL_001"
    add(
      row(
        "validation",
        "alternating validator pair \{i + 1}",
        "private",
        100 + i,
        "revalidate",
        reason=Some(reason),
        stored_headers=[("Cache-Control", "max-age=60"), validators[i % 2]],
      ),
    )
  }
}

///|
fn build_shared_auth_matrix_family() -> Unit {
  let qualifiers : Array[(String, String)] = [
    ("public", "public, max-age=60"),
    ("s-maxage=60", "s-maxage=60"),
    ("must-revalidate", "must-revalidate, max-age=60"),
    ("proxy-revalidate", "proxy-revalidate, max-age=60"),
    ("no-store", "no-store"),
  ]
  for i in 0..<qualifiers.length() {
    let qualifier = qualifiers[i].0
    let directive = qualifiers[i].1
    add(
      row(
        "authorization",
        "authorized shared entry with \{qualifier}",
        "shared",
        10,
        if qualifier == "no-store" {
          "fetch"
        } else {
          "hit"
        },
        reason=Some(
          if qualifier == "no-store" {
            "MC_STORE_002"
          } else if qualifier == "s-maxage=60" {
            "MC_FRESH_002"
          } else {
            "MC_FRESH_001"
          },
        ),
        request_headers=[("Authorization", "Bearer token")],
        stored_headers=[("Cache-Control", directive)],
      ),
    )
  }
  for i in 0..<6 {
    add(
      row(
        "authorization",
        "authorized private-mode matrix \{i + 1}",
        "private",
        10 + i,
        "hit",
        reason=Some("MC_FRESH_006"),
        request_headers=[("Authorization", "Bearer t\{i}")],
      ),
    )
  }
}

///|
fn build_vary_matrix_family() -> Unit {
  let specs : Array[(String, Array[(String, String)])] = [
    ("Accept-Encoding", [("Accept-Encoding", "gzip")]),
    ("Accept-Encoding", [("Accept-Encoding", "br")]),
    (
      "Accept-Language, User-Agent",
      [("Accept-Language", "en"), ("User-Agent", "ua/1")],
    ),
    (
      "Accept-Language, User-Agent",
      [("Accept-Language", "zh"), ("User-Agent", "ua/2")],
    ),
    ("X-Grid", [("X-Grid", "a")]),
    ("X-Grid", [("X-Grid", "b")]),
    ("X-Grid", [("X-Grid", "c")]),
    ("If-Header", [("If-Header", "v1")]),
    ("If-Header", [("If-Header", "v2")]),
    ("Multi-A", [("Multi-A", "1")]),
    ("Multi-B", [("Multi-B", "2")]),
    ("Multi-C", [("Multi-C", "3")]),
  ]
  for i in 0..<specs.length() {
    let spec = specs[i]
    add(
      row(
        "vary",
        "variant grid case \{i + 1}",
        "private",
        10,
        "hit",
        reason=None,
        request_headers=spec.1,
        stored_headers=[("Cache-Control", "max-age=60"), ("Vary", spec.0)],
      ),
    )
  }
}
