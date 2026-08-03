///|
/// Return the canonical representation used for case-insensitive HTTP field
/// names. Leading and trailing whitespace is ignored so adapter input can be
/// normalized at the boundary.
pub fn normalize_header_name(name : String) -> String {
  name.trim().to_lower().to_owned()
}

///|
/// Remove optional whitespace around an HTTP field value without changing
/// meaningful whitespace inside the value.
pub fn normalize_header_value(value : String) -> String {
  value.trim(chars=" \t").to_owned()
}

///|
fn is_ascii_alpha(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
}

///|
fn is_ascii_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn is_http_token_punctuation(ch : Char) -> Bool {
  ch == '!' ||
  ch == '#' ||
  ch == '$' ||
  ch == '%' ||
  ch == '&' ||
  ch == '\'' ||
  ch == '*' ||
  ch == '+' ||
  ch == '-' ||
  ch == '.' ||
  ch == '^' ||
  ch == '_' ||
  ch == '`' ||
  ch == '|' ||
  ch == '~'
}

///|
/// Check the RFC 9110 token grammar used by HTTP field names.
pub fn is_valid_header_name(name : String) -> Bool {
  let normalized = normalize_header_name(name)
  if normalized == "" {
    return false
  }
  for ch in normalized {
    if !is_ascii_alpha(ch) &&
      !is_ascii_digit(ch) &&
      !is_http_token_punctuation(ch) {
      return false
    }
  }
  true
}

///|
/// A case-insensitive, insertion-ordered collection of HTTP fields.
///
/// Repeated fields are retained as separate values. `contains` distinguishes a
/// missing field from a present field whose value is empty, which is required
/// for correct `Vary` matching.
pub struct HeaderMap {
  values : Map[String, Array[String]]
} derive(Eq, Debug)

///|
pub fn HeaderMap::new() -> HeaderMap {
  HeaderMap::{ values: Map([]) }
}

///|
pub fn HeaderMap::from_pairs(pairs : Array[(String, String)]) -> HeaderMap {
  let headers = HeaderMap::new()
  for pair in pairs {
    ignore(headers.append(pair.0, pair.1))
  }
  headers
}

///|
/// Create a deep copy so callers cannot mutate arrays held by the source map.
pub fn HeaderMap::copy(self : HeaderMap) -> HeaderMap {
  let result = HeaderMap::new()
  self.values.each(fn(name, values) { result.values[name] = values.copy() })
  result
}

///|
/// Replace all existing values for `name`. Invalid field names are rejected and
/// leave the map unchanged.
pub fn HeaderMap::set(self : HeaderMap, name : String, value : String) -> Bool {
  if !is_valid_header_name(name) {
    return false
  }
  self.values[normalize_header_name(name)] = [normalize_header_value(value)]
  true
}

///|
/// Add one value for `name`, retaining previous values.
pub fn HeaderMap::append(
  self : HeaderMap,
  name : String,
  value : String,
) -> Bool {
  if !is_valid_header_name(name) {
    return false
  }
  let key = normalize_header_name(name)
  let normalized = normalize_header_value(value)
  match self.values.get(key) {
    Some(values) => values.push(normalized)
    None => self.values[key] = [normalized]
  }
  true
}

///|
pub fn HeaderMap::remove(self : HeaderMap, name : String) -> Bool {
  let key = normalize_header_name(name)
  if self.values.contains(key) {
    self.values.remove(key)
    true
  } else {
    false
  }
}

///|
pub fn HeaderMap::contains(self : HeaderMap, name : String) -> Bool {
  self.values.contains(normalize_header_name(name))
}

///|
/// Return a defensive copy of every value for `name`.
pub fn HeaderMap::get_all(self : HeaderMap, name : String) -> Array[String] {
  match self.values.get(normalize_header_name(name)) {
    Some(values) => values.copy()
    None => []
  }
}

///|
pub fn HeaderMap::get_first(self : HeaderMap, name : String) -> String? {
  match self.values.get(normalize_header_name(name)) {
    Some(values) => if values.length() == 0 { None } else { Some(values[0]) }
    None => None
  }
}

///|
/// Combine repeated field values using the comma convention used by the cache
/// directives handled by MoonCache.
pub fn HeaderMap::get(self : HeaderMap, name : String) -> String? {
  let values = self.get_all(name)
  if values.length() == 0 {
    None
  } else {
    Some(values.join(", "))
  }
}

///|
pub fn HeaderMap::length(self : HeaderMap) -> Int {
  self.values.length()
}

///|
pub fn HeaderMap::is_empty(self : HeaderMap) -> Bool {
  self.values.is_empty()
}

///|
fn compare_normalized_header_names(left : String, right : String) -> Int {
  let limit = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index = 0; index < limit; index = index + 1 {
    let left_code = left.code_unit_at(index)
    let right_code = right.code_unit_at(index)
    if left_code < right_code {
      return -1
    }
    if left_code > right_code {
      return 1
    }
  }
  if left.length() < right.length() {
    -1
  } else if left.length() > right.length() {
    1
  } else {
    0
  }
}

///|
/// Return canonical field names in deterministic lexical order.
pub fn HeaderMap::names(self : HeaderMap) -> Array[String] {
  let result = self.values.keys().to_array()
  result.sort_by(compare_normalized_header_names)
  result
}

///|
/// Return normalized field/value pairs in deterministic name order while
/// preserving value order within each repeated field.
pub fn HeaderMap::pairs(self : HeaderMap) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  for name in self.names() {
    for value in self.get_all(name) {
      result.push((name, value))
    }
  }
  result
}

///|
fn is_sensitive_header_name(name : String) -> Bool {
  let key = normalize_header_name(name)
  key == "authorization" ||
  key == "proxy-authorization" ||
  key == "cookie" ||
  key == "set-cookie"
}

///|
/// Return a copy suitable for diagnostics. Credential and cookie values are
/// replaced while their presence remains visible.
pub fn HeaderMap::redacted(self : HeaderMap) -> HeaderMap {
  let result = HeaderMap::new()
  for name in self.names() {
    if is_sensitive_header_name(name) {
      ignore(result.set(name, "<redacted>"))
    } else {
      for value in self.get_all(name) {
        ignore(result.append(name, value))
      }
    }
  }
  result
}

///|
/// Overlay every field from `updates`, replacing existing repeated values.
pub fn HeaderMap::overlay(self : HeaderMap, updates : HeaderMap) -> HeaderMap {
  let result = self.copy()
  for name in updates.names() {
    let values = updates.get_all(name)
    if values.length() > 0 {
      ignore(result.set(name, values[0]))
      for index = 1; index < values.length(); index = index + 1 {
        ignore(result.append(name, values[index]))
      }
    }
  }
  result
}
