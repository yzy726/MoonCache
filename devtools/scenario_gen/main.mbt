///|
priv struct Row {
  family : String
  name : String
  mode : String
  now : Int
  http_method : String
  uri : String
  request_headers : Array[(String, String)]
  stored_status : Int?
  stored_headers : Array[(String, String)]
  stored_request_time : Int
  stored_response_time : Int
  body : String
  complete : Bool
  expected_action : String
  expected_reason : String?
}

///|
fn Row::to_scenario(self : Row) -> @mooncache.CacheScenario {
  let headers : Map[String, String] = Map([])
  for pair in self.request_headers {
    headers[pair.0] = pair.1
  }
  let request = @mooncache.ScenarioRequest::{
    http_method: self.http_method,
    uri: self.uri,
    headers,
    request_time: None,
  }
  let stored : @mooncache.ScenarioResponse? = match self.stored_status {
    Some(status) => {
      let response_headers : Map[String, String] = Map([])
      for pair in self.stored_headers {
        response_headers[pair.0] = pair.1
      }
      Some(@mooncache.ScenarioResponse::{
        status,
        headers: response_headers,
        request_time: Some(self.stored_request_time),
        response_time: Some(self.stored_response_time),
        body: Some(self.body),
        complete: Some(self.complete),
      })
    }
    None => None
  }
  let expected : @mooncache.ScenarioExpected? = Some(@mooncache.ScenarioExpected::{
    action: self.expected_action,
    reason: self.expected_reason,
  })
  @mooncache.CacheScenario::{
    name: self.name,
    mode: self.mode,
    now: self.now,
    request,
    stored_response: stored,
    upstream_response: None,
    expected,
  }
}

///|
fn row(
  family : String,
  name : String,
  mode : String,
  now : Int,
  action : String,
  reason? : String? = None,
  http_method? : String = "GET",
  uri? : String = "https://example.test/scenario",
  request_headers? : Array[(String, String)] = [],
  stored_status? : Int? = Some(200),
  stored_headers? : Array[(String, String)] = [("Cache-Control", "max-age=60")],
  stored_request_time? : Int = 0,
  stored_response_time? : Int = 0,
  body? : String = "payload",
  complete? : Bool = true,
) -> Row {
  Row::{
    family,
    name,
    mode,
    now,
    http_method,
    uri,
    request_headers,
    stored_status,
    stored_headers,
    stored_request_time,
    stored_response_time,
    body,
    complete,
    expected_action: action,
    expected_reason: reason,
  }
}

///|
let rows : Array[Row] = []

///|
fn add(r : Row) -> Unit {
  rows.push(r)
}

///|
fn slugify(value : String) -> String {
  value
  .to_lower()
  .replace_all(old=" ", new="-")
  .replace_all(old=",", new="")
  .replace_all(old="=", new="-")
  .replace_all(old="/", new="-")
  .replace_all(old=":", new="-")
  .replace_all(old="\"", new="")
  .replace_all(old="'", new="")
  .replace_all(old="(", new="")
  .replace_all(old=")", new="")
  .replace_all(old="+", new="-")
  .replace_all(old="--", new="-")
}

///|
fn pad(value : Int) -> String {
  if value < 10 {
    "00\{value}"
  } else if value < 100 {
    "0\{value}"
  } else {
    "\{value}"
  }
}

///|
fn fresh_boundary_rows(
  family : String,
  label : String,
  lifetime : Int,
  mode : String,
  headers : Array[(String, String)],
) -> Unit {
  let cases : Array[(Int, Int)] = [
    (lifetime - 1, 0),
    (lifetime, 1),
    (lifetime + 30, 2),
  ]
  for i in 0..<cases.length() {
    let offset = cases[i].0
    let verdict_index = cases[i].1
    let verdict = if verdict_index == 0 { "hit" } else { "fetch" }
    let action = if verdict_index == 0 { "hit" } else { "miss" }
    let reason = if verdict_index == 0 {
      if mode == "shared" {
        Some("MC_FRESH_002")
      } else {
        Some("MC_FRESH_001")
      }
    } else {
      Some("MC_FRESH_007")
    }
    add(
      row(
        family,
        "\{label} age \{offset} must \{verdict}",
        mode,
        offset,
        action,
        reason~,
        stored_headers=headers,
      ),
    )
  }
}

///|
fn main {
  build_storage_family()
  build_freshness_family()
  build_age_family()
  build_request_family()
  build_validation_family()
  build_vary_family()
  build_shared_family()
  build_authorization_family()
  build_method_family()
  build_heuristic_family()
  build_boundary_matrix_family()
  build_request_matrix_family()
  build_storage_mode_matrix_family()
  build_validation_extra_family()
  build_shared_auth_matrix_family()
  build_vary_matrix_family()
  try {
    write_rows("testdata/scenarios")
    println("generated \{rows.length()} scenarios into testdata/scenarios")
  } catch {
    error => println("failed: \{error}")
  }
}

///|
fn write_rows(root : String) -> Unit raise {
  let mut index = 1
  for r in rows {
    let filename = "\{pad(index)}-\{r.family}-\{slugify(r.name)}.json"
    @fs.write_string_to_file(
      "\{root}/\{filename}",
      "\{@mooncache.scenario_to_json(r.to_scenario())}\n",
    )
    index = index + 1
  }
}
