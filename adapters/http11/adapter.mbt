///|
/// Conversion failures are kept inside the optional adapter package.
pub suberror Http11AdapterError {
  AbsoluteUriRequired(String)
  InvalidHeaderName(String)
} derive(Eq, Debug)

///|
pub fn Http11AdapterError::message(self : Http11AdapterError) -> String {
  match self {
    AbsoluteUriRequired(uri) =>
      "an absolute HTTP(S) URI is required, received: \{uri}"
    InvalidHeaderName(name) => "invalid HTTP header name: \{name}"
  }
}

///|
fn header_map_from_pairs(
  pairs : Array[(String, String)],
) -> @mooncache.HeaderMap raise Http11AdapterError {
  let headers = @mooncache.HeaderMap::new()
  for pair in pairs {
    guard headers.append(pair.0, pair.1) else {
      raise InvalidHeaderName(pair.0)
    }
  }
  headers
}

///|
fn bytes_from_array(bytes : Array[Byte]) -> Bytes {
  Bytes::from_array(bytes)
}

///|
fn array_from_bytes(bytes : Bytes) -> Array[Byte] {
  let result = []
  for byte in bytes {
    result.push(byte)
  }
  result
}

///|
fn checked_absolute_uri(uri : String) -> String raise Http11AdapterError {
  guard @mooncache.normalize_cache_uri(uri) is Some(_) else {
    raise AbsoluteUriRequired(uri)
  }
  uri
}

///|
/// Convert an HTTP11 request whose request target is already absolute.
///
/// Origin-form targets such as `/assets/app.js` must use
/// `request_to_runtime_at_uri` so the integrating transport supplies the
/// scheme and authority it used for the connection.
pub fn request_to_runtime(
  request : @wire11.Request,
  request_time : @mooncache.Timestamp,
) -> @mooncache.RuntimeRequest raise Http11AdapterError {
  request_to_runtime_at_uri(request, request.uri, request_time)
}

///|
/// Convert an HTTP11 request while explicitly supplying its absolute URI.
pub fn request_to_runtime_at_uri(
  request : @wire11.Request,
  absolute_uri : String,
  request_time : @mooncache.Timestamp,
) -> @mooncache.RuntimeRequest raise Http11AdapterError {
  let uri = checked_absolute_uri(absolute_uri)
  let headers = header_map_from_pairs(request.headers)
  let meta = @mooncache.RequestMeta::new(
    request.http_method,
    uri,
    headers,
    request_time,
  )
  @mooncache.RuntimeRequest::new(meta, bytes_from_array(request.body))
}

///|
/// Convert a complete or incomplete HTTP11 response into an origin result.
///
/// The caller owns the timestamps because the MoonCache core never reads a
/// system clock.
pub fn response_to_transport(
  response : @wire11.Response,
  request_time : @mooncache.Timestamp,
  response_time : @mooncache.Timestamp,
  body_complete? : Bool = true,
) -> @mooncache.TransportResponse raise Http11AdapterError {
  let headers = header_map_from_pairs(response.headers)
  let meta = @mooncache.ResponseMeta::new(
    response.status_code,
    headers,
    request_time,
    response_time,
    body_complete,
  )
  @mooncache.TransportResponse::new(meta, bytes_from_array(response.body))
}

///|
fn default_reason_phrase(status : Int) -> String {
  match status {
    100 => "Continue"
    101 => "Switching Protocols"
    200 => "OK"
    201 => "Created"
    202 => "Accepted"
    203 => "Non-Authoritative Information"
    204 => "No Content"
    205 => "Reset Content"
    206 => "Partial Content"
    300 => "Multiple Choices"
    301 => "Moved Permanently"
    302 => "Found"
    303 => "See Other"
    304 => "Not Modified"
    305 => "Use Proxy"
    307 => "Temporary Redirect"
    308 => "Permanent Redirect"
    400 => "Bad Request"
    401 => "Unauthorized"
    403 => "Forbidden"
    404 => "Not Found"
    405 => "Method Not Allowed"
    408 => "Request Timeout"
    409 => "Conflict"
    410 => "Gone"
    411 => "Length Required"
    412 => "Precondition Failed"
    413 => "Content Too Large"
    414 => "URI Too Long"
    415 => "Unsupported Media Type"
    416 => "Range Not Satisfiable"
    417 => "Expectation Failed"
    421 => "Misdirected Request"
    422 => "Unprocessable Content"
    426 => "Upgrade Required"
    428 => "Precondition Required"
    429 => "Too Many Requests"
    431 => "Request Header Fields Too Large"
    500 => "Internal Server Error"
    501 => "Not Implemented"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    504 => "Gateway Timeout"
    505 => "HTTP Version Not Supported"
    _ => ""
  }
}

///|
/// Convert a MoonCache request back to the HTTP11 transport model.
pub fn runtime_request_to_http11(
  request : @mooncache.RuntimeRequest,
) -> @wire11.Request {
  @wire11.Request::{
    http_method: request.meta.http_method,
    uri: request.meta.uri,
    version: "HTTP/1.1",
    headers: request.meta.headers.pairs(),
    body: array_from_bytes(request.body),
  }
}

///|
fn response_meta_to_http11(
  meta : @mooncache.ResponseMeta,
  body : Bytes,
) -> @wire11.Response {
  @wire11.Response::{
    version: "HTTP/1.1",
    status_code: meta.status,
    reason_phrase: default_reason_phrase(meta.status),
    headers: meta.headers.pairs(),
    body: array_from_bytes(body),
  }
}

///|
/// Convert an origin response back to the HTTP11 response model.
pub fn transport_response_to_http11(
  response : @mooncache.TransportResponse,
) -> @wire11.Response {
  response_meta_to_http11(response.meta, response.body)
}

///|
/// Convert a final cached runtime response back to HTTP11.
pub fn runtime_response_to_http11(
  response : @mooncache.RuntimeResponse,
) -> @wire11.Response {
  response_meta_to_http11(response.meta, response.body)
}
