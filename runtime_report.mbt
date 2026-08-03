///|
pub fn RuntimeResponse::is_cache_reuse(self : RuntimeResponse) -> Bool {
  self.source is CacheSource ||
  self.source is RevalidatedSource ||
  self.source is StaleSource
}

///|
fn response_headers_to_json(headers : HeaderMap) -> Json {
  let object : Map[String, Json] = Map([])
  let safe = headers.redacted()
  for name in safe.names() {
    let values = safe.get_all(name)
    if values.length() == 1 {
      object[name] = Json::string(values[0])
    } else {
      object[name] = Json::array(values.map(fn(value) { Json::string(value) }))
    }
  }
  Json::object(object)
}

///|
/// Structured runtime report. Response bodies are deliberately excluded;
/// their size is enough for diagnostics and cannot leak cached content.
pub fn RuntimeResponse::to_json(self : RuntimeResponse) -> Json {
  Json::object({
    "source": self.source.label(),
    "status": self.meta.status,
    "headers": response_headers_to_json(self.meta.headers),
    "body_bytes": self.body.length(),
    "body_complete": self.meta.body_complete,
    "cache_reuse": self.is_cache_reuse(),
    "trace": self.trace.to_json(),
  })
}

///|
pub fn RuntimeResponse::json_report(self : RuntimeResponse) -> String {
  self.to_json().stringify(indent=2)
}

///|
pub fn RuntimeResponse::text_report(self : RuntimeResponse) -> String {
  let lines = [
    "Source: \{self.source.label()}",
    "Status: \{self.meta.status}",
    "Body bytes: \{self.body.length()}",
    "Body complete: \{self.meta.body_complete}",
  ]
  for pair in self.meta.headers.redacted().pairs() {
    lines.push("Response header: \{pair.0}: \{pair.1}")
  }
  lines.push(self.trace.text_report())
  lines.join("\n")
}
