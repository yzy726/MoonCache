///|
extern "C" fn wall_clock_seconds_ffi() -> Int64 = "mooncache_wall_clock_seconds"

///|
fn wall_clock() -> @mooncache.Timestamp {
  @mooncache.Timestamp::from_seconds(wall_clock_seconds_ffi())
}

///|
fn hop_by_hop_header(name : String) -> Bool {
  match name.to_lower() {
    "connection"
    | "keep-alive"
    | "proxy-authenticate"
    | "proxy-authorization"
    | "te"
    | "trailer"
    | "transfer-encoding"
    | "upgrade" => true
    _ => false
  }
}

///|
fn normalize_upstream_origin(origin : String) -> String raise CliArgumentError {
  let trimmed = origin.trim()
  guard trimmed != "" else {
    raise CliArgumentError("--upstream requires host[:port]")
  }
  let base = if trimmed.contains("://") { trimmed } else { "http://\{trimmed}" }
  let limit = if base == "http:///" || !base.has_suffix("/") {
    base.length()
  } else {
    base.length() - 1
  }
  let builder = StringBuilder::new()
  let mut index = 0
  for ch in base {
    if index < limit {
      builder.write_char(ch)
    }
    index = index + 1
  }
  builder.to_string()
}

///|
fn status_reason(status : Int) -> String {
  match status {
    200 => "OK"
    201 => "Created"
    202 => "Accepted"
    204 => "No Content"
    301 => "Moved Permanently"
    302 => "Found"
    304 => "Not Modified"
    307 => "Temporary Redirect"
    308 => "Permanent Redirect"
    400 => "Bad Request"
    401 => "Unauthorized"
    403 => "Forbidden"
    404 => "Not Found"
    405 => "Method Not Allowed"
    408 => "Request Timeout"
    410 => "Gone"
    412 => "Precondition Failed"
    429 => "Too Many Requests"
    500 => "Internal Server Error"
    501 => "Not Implemented"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    504 => "Gateway Timeout"
    _ => ""
  }
}

///|
fn proxy_request_headers(request : @http.Request) -> @mooncache.HeaderMap {
  let headers = @mooncache.HeaderMap::new()
  for name, value in request.headers {
    if !hop_by_hop_header(name) && name.to_lower() != "host" {
      ignore(headers.append(name, value))
    }
  }
  headers
}

///|
async fn[S : @mooncache.CacheStore] handle_proxy_request(
  client : @async_http.CachedClient[S, @async_http.MoonbitAsyncHttpTransport],
  origin : String,
  request : @http.Request,
  body : &@io.Reader,
  connection : @http.ServerConnection,
) -> Unit {
  while body.read_some() is Some(_) {

  }
  match request.meth {
    Get | Head => {
      let target = "\{origin}\{request.path}"
      let runtime_request = if request.meth is Head {
        @mooncache.RuntimeRequest::head(target).with_headers(
          proxy_request_headers(request),
        )
      } else {
        @mooncache.RuntimeRequest::get(target).with_headers(
          proxy_request_headers(request),
        )
      }
      let response = client.execute(runtime_request)
      connection.send_response(
        response.meta.status,
        status_reason(response.meta.status),
        extra_headers=@async_http.headers_to_async_http(response.meta.headers),
      )
      if !(request.meth is Head) && response.body.length() > 0 {
        connection.write(response.body)
      }
      connection.end_response()
    }
    _ => {
      connection.send_response(
        405,
        "Method Not Allowed",
        extra_headers=Map([("Allow", "GET, HEAD")]),
      )
      connection.write_string(
        "mooncache demo proxy supports GET and HEAD only\n",
      )
      connection.end_response()
    }
  }
}

///|
fn print_proxy_banner(server : @http.Server, origin : String) -> Unit {
  println("mooncache demo proxy")
  println("listening: http://127.0.0.1:\{server.addr.port()}")
  println("upstream:  \{origin}")
  println("(development demo; no TLS, CONNECT, or production hardening)")
}

///|
async fn[S : @mooncache.CacheStore] caching_proxy_loop(
  server : @http.Server,
  upstream : String,
  build_store : () -> S raise,
) -> Unit {
  let origin = normalize_upstream_origin(upstream)
  let transport = @async_http.MoonbitAsyncHttpTransport::new(wall_clock)
  let store = build_store()
  let client = @async_http.CachedClient::new(
    store,
    transport,
    @mooncache.CacheOptions::shared_cache(),
    clock=wall_clock,
  )
  print_proxy_banner(server, origin)
  server.run_forever() <| ((request, body, connection) => {
    handle_proxy_request(client, origin, request, body, connection) catch {
      error => {
        let message = @debug.to_string(error)
        try! connection.send_response(
          502,
          "Bad Gateway",
          extra_headers=Map([("Via", "mooncache-demo")]),
        )
        try! connection.write_string("upstream failure: \{message}\n")
        try! connection.end_response()
      }
    }
  })
}

///|
async fn serve_async(
  listen : String,
  upstream : String,
  store_path : String?,
) -> Unit {
  let server = @http.Server(@socket.Addr::parse(listen))
  match store_path {
    Some(path) =>
      caching_proxy_loop(server, upstream, () => open_cli_store(path))
    None =>
      caching_proxy_loop(server, upstream, () => {
        @mooncache.MemoryStore::default()
      })
  }
}

///|
async fn serve_entry(
  listen : String,
  upstream : String,
  store_path : String?,
) -> Unit {
  serve_async(listen, upstream, store_path) catch {
    error => {
      println("mooncache: \{@debug.to_string(error)}")
      process_exit(2)
    }
  }
}

///|
fn serve_command(
  listen : String,
  upstream : String,
  store_path : String?,
) -> Int {
  @async.run_async_main(() => serve_entry(listen, upstream, store_path))
  0
}
