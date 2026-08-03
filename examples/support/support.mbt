///|
pub fn response(
  status : Int,
  headers : Array[(String, String)],
  body : Bytes,
  request_time : Int64,
  response_time : Int64,
) -> @mooncache.TransportResponse {
  @mooncache.TransportResponse::new(
    @mooncache.ResponseMeta::complete(
      status,
      @mooncache.HeaderMap::from_pairs(headers),
      @mooncache.Timestamp::from_seconds(request_time),
      @mooncache.Timestamp::from_seconds(response_time),
    ),
    body,
  )
}

///|
pub fn request(
  http_method : String,
  uri : String,
  headers : Array[(String, String)],
) -> @mooncache.RuntimeRequest {
  @mooncache.RuntimeRequest::new(
    @mooncache.RequestMeta::new(
      http_method,
      uri,
      @mooncache.HeaderMap::from_pairs(headers),
      @mooncache.Timestamp::zero(),
    ),
    b"",
  )
}

///|
pub fn require(condition : Bool, message : String) -> Unit raise {
  guard condition else { fail("example assertion failed: \{message}") }
}

///|
pub fn print_result(
  label : String,
  response : @mooncache.RuntimeResponse,
) -> Unit {
  println(
    "\{label}: source=\{response.source.label()}, decision=\{response.trace.action.label()}",
  )
}
