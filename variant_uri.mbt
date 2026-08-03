///|
fn first_uri_delimiter(value : String) -> Int {
  let mut result = value.length()
  for index = 0; index < value.length(); index = index + 1 {
    let code = value.code_unit_at(index)
    if code == '/' || code == '?' || code == '#' {
      result = index
      break
    }
  }
  result
}

///|
fn count_code_unit(value : String, expected : UInt16) -> Int {
  let mut count = 0
  for index = 0; index < value.length(); index = index + 1 {
    if value.code_unit_at(index) == expected {
      count = count + 1
    }
  }
  count
}

///|
fn normalized_port(value : String) -> String? {
  if value == "" {
    return None
  }
  let parsed = parse_decimal_int(value)
  match parsed {
    Some(port) =>
      if port >= 0 && port <= 65_535 {
        Some(port.to_string())
      } else {
        None
      }
    None => None
  }
}

///|
fn normalize_authority(authority : String, scheme : String) -> String? {
  if authority == "" || authority.contains("@") {
    return None
  }
  if authority.has_prefix("[") {
    guard authority.find("]") is Some(close) else { return None }
    let host = authority.sub(start=0, end=close + 1).to_lower().to_owned()
    let suffix = authority.sub(start=close + 1).to_owned()
    if suffix == "" {
      return Some(host)
    }
    if !suffix.has_prefix(":") {
      return None
    }
    let raw_port = suffix.sub(start=1).to_owned()
    guard normalized_port(raw_port) is Some(port) else { return None }
    if (scheme == "http" && port == "80") ||
      (scheme == "https" && port == "443") {
      Some(host)
    } else {
      Some("\{host}:\{port}")
    }
  } else {
    if count_code_unit(authority, ':') > 1 {
      return None
    }
    let (raw_host, raw_port) = match authority.rev_split_once(":") {
      Some((host, port)) => (host.to_owned(), Some(port.to_owned()))
      None => (authority, None)
    }
    let host = raw_host.to_lower()
    if host == "" {
      return None
    }
    match raw_port {
      Some(raw) => {
        guard normalized_port(raw) is Some(port) else { return None }
        if (scheme == "http" && port == "80") ||
          (scheme == "https" && port == "443") {
          Some(host)
        } else {
          Some("\{host}:\{port}")
        }
      }
      None => Some(host)
    }
  }
}

///|
fn remove_dot_segments(path : String) -> String {
  let trailing = path.has_suffix("/") ||
    path.has_suffix("/.") ||
    path.has_suffix("/..")
  let segments : Array[String] = []
  for view in path.split("/") {
    let segment = view.to_owned()
    match segment {
      "." => ()
      ".." => if segments.length() > 1 { ignore(segments.pop()) }
      _ => segments.push(segment)
    }
  }
  let mut result = segments.join("/")
  if result == "" {
    result = "/"
  } else if !result.has_prefix("/") {
    result = "/\{result}"
  }
  if trailing && result != "/" && !result.has_suffix("/") {
    result = "\{result}/"
  }
  result
}

///|
/// Normalize an absolute HTTP(S) URI for primary cache lookup.
///
/// Scheme and host are lower-cased, default ports and fragments are removed,
/// an empty path becomes `/`, and literal dot segments are resolved. Query text
/// and percent-encoded octets are otherwise preserved.
pub fn normalize_cache_uri(uri : String) -> String? {
  let trimmed = uri.trim(chars=" \t").to_owned()
  guard trimmed.split_once("://") is Some((raw_scheme, remainder_view)) else {
    return None
  }
  let scheme = raw_scheme.to_lower().to_owned()
  if scheme != "http" && scheme != "https" {
    return None
  }
  let remainder = remainder_view.to_owned()
  let boundary = first_uri_delimiter(remainder)
  let authority_text = remainder.sub(start=0, end=boundary).to_owned()
  guard normalize_authority(authority_text, scheme) is Some(authority) else {
    return None
  }
  let suffix_with_fragment = remainder.sub(start=boundary).to_owned()
  let suffix = match suffix_with_fragment.split_once("#") {
    Some((before, _)) => before.to_owned()
    None => suffix_with_fragment
  }
  let (raw_path, query) = match suffix.split_once("?") {
    Some((path, query)) => (path.to_owned(), Some(query.to_owned()))
    None => (suffix, None)
  }
  if raw_path != "" && !raw_path.has_prefix("/") {
    return None
  }
  let path = remove_dot_segments(if raw_path == "" { "/" } else { raw_path })
  let query_suffix = match query {
    Some(value) => "?\{value}"
    None => ""
  }
  Some("\{scheme}://\{authority}\{path}\{query_suffix}")
}

///|
pub fn cache_origin(uri : String) -> String? {
  guard normalize_cache_uri(uri) is Some(normalized) else { return None }
  guard normalized.split_once("://") is Some((scheme, remainder)) else {
    return None
  }
  let rest = remainder.to_owned()
  let boundary = first_uri_delimiter(rest)
  Some("\{scheme.to_owned()}://\{rest.sub(start=0, end=boundary).to_owned()}")
}

///|
pub fn same_cache_origin(left : String, right : String) -> Bool {
  match (cache_origin(left), cache_origin(right)) {
    (Some(left_origin), Some(right_origin)) => left_origin == right_origin
    _ => false
  }
}

///|
/// Construct the primary key. HEAD shares the GET lookup namespace while
/// retaining its request method in `RequestMeta`.
pub fn primary_cache_key(request : RequestMeta) -> PrimaryCacheKey? {
  guard normalize_cache_uri(request.uri) is Some(uri) else { return None }
  let key_method = if request.http_method == "HEAD" {
    "GET"
  } else {
    request.http_method
  }
  Some(PrimaryCacheKey::new(key_method, uri))
}

///|
pub fn PrimaryCacheKey::from_request(request : RequestMeta) -> PrimaryCacheKey? {
  primary_cache_key(request)
}
