///|
test "CLI defaults to help" {
  assert_true(parse_command([]) is Help)
}

///|
test "CLI removes the executable path from environment arguments" {
  assert_eq(command_args(["mooncache"]), [])
  assert_eq(command_args(["mooncache", "unknown"]), ["unknown"])
  assert_eq(command_args(["mooncache", "validate", "case.json"]), [
    "validate", "case.json",
  ])
}

///|
test "CLI parses text explain" {
  assert_true(
    parse_command(["explain", "case.json"]) is Explain("case.json", TextOutput),
  )
}

///|
test "CLI parses JSON explain" {
  assert_true(
    parse_command(["explain", "case.json", "--json"])
    is Explain("case.json", JsonOutput),
  )
}

///|
test "CLI parses JSON validate" {
  assert_true(
    parse_command(["validate", "case.json", "--json"])
    is Validate("case.json", JsonOutput),
  )
}

///|
test "CLI parses directory replay" {
  assert_true(parse_command(["replay", "cases"]) is Replay("cases", TextOutput))
}

///|
test "CLI parses version aliases" {
  assert_true(parse_command(["version"]) is Version)
  assert_true(parse_command(["--version"]) is Version)
}

///|
test "CLI rejects unknown command" {
  let result : Result[CliCommand, CliArgumentError] = Ok(
    parse_command(["unknown"]),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(CliArgumentError("unknown command: unknown")))
}

///|
test "CLI rejects unknown output option" {
  let result : Result[CliCommand, CliArgumentError] = Ok(
    parse_command(["explain", "case.json", "--yaml"]),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(CliArgumentError("unknown option: --yaml")))
}

///|
test "CLI joins portable directory paths" {
  assert_eq(join_path("cases", "one.json"), "cases/one.json")
  assert_eq(join_path("cases/", "one.json"), "cases/one.json")
  assert_eq(join_path("cases\\", "one.json"), "cases\\one.json")
}

///|
test "CLI path comparator produces lexical scenario order" {
  let names = ["08.json", "02.json", "10.json", "01.json"]
  names.sort_by(compare_cli_paths)
  assert_eq(names, ["01.json", "02.json", "08.json", "10.json"])
}

///|
test "CLI validation JSON is structured" {
  let analysis = @mooncache.ScenarioAnalysis::{
    name: "demo",
    trace: @mooncache.CacheTrace::new(Fetch),
    valid: false,
    errors: ["mismatch"],
  }
  let report = validation_json(analysis)
  assert_true(report.contains("\"name\": \"demo\""))
  assert_true(report.contains("\"valid\": false"))
  assert_true(report.contains("\"mismatch\""))
}

///|
test "CLI replay JSON includes summary and cases" {
  let report = replay_json(
    "cases",
    [
      ReplayCase::{
        file: "cases/one.json",
        name: "one",
        action: Some("FETCH"),
        valid: true,
        errors: [],
      },
    ],
    1,
    0,
  )
  assert_true(report.contains("\"passed\": 1"))
  assert_true(report.contains("\"action\": \"FETCH\""))
  assert_true(report.contains("\"valid\": true"))
}

///|
fn cli_test_entry(uri : String, tick : Int64) -> @mooncache.StoredEntry {
  let headers = @mooncache.HeaderMap::new()
  ignore(headers.append("Cache-Control", "max-age=60"))
  let request = @mooncache.RequestMeta::new(
    "GET",
    uri,
    @mooncache.HeaderMap::new(),
    @mooncache.Timestamp::from_seconds(tick),
  )
  let response = @mooncache.ResponseMeta::complete(
    200,
    headers,
    @mooncache.Timestamp::from_seconds(tick),
    @mooncache.Timestamp::from_seconds(tick),
  )
  let primary = @mooncache.PrimaryCacheKey::from_request(request).unwrap()
  let variant = @mooncache.build_variant_key(
    request.headers,
    @mooncache.parse_vary(response.headers),
  ).unwrap()
  @mooncache.StoredEntry::new(
    primary,
    variant,
    request,
    response,
    b"payload",
    @mooncache.StoredPolicy::cacheable(
      @mooncache.DeltaSeconds::from_seconds(60),
      false,
    ),
    @mooncache.Timestamp::from_seconds(tick),
  )
}

///|
fn prepare_cli_store(
  root : String,
  entries : Array[@mooncache.StoredEntry],
) -> Unit raise {
  let store = @file_store.FileStore::open(root)
  for entry in entries {
    ignore(store.put(entry))
  }
}

///|
test "CLI parses store stats with --store option" {
  assert_true(
    parse_command(["stats", "--store", "cachedir"])
    is Stats("cachedir", TextOutput),
  )
  assert_true(
    parse_command(["stats", "--store", "cachedir", "--json"])
    is Stats("cachedir", JsonOutput),
  )
}

///|
test "CLI rejects stats without --store path" {
  let result : Result[CliCommand, CliArgumentError] = Ok(
    parse_command(["stats"]),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(CliArgumentError("stats requires --store <path>")))
}

///|
test "CLI store stats reports persisted entry counts" {
  let root = "target/mooncache_cli_tests/stats"
  prepare_cli_store(root, [cli_test_entry("https://example.test/data", 100)])
  let text = store_stats_report(root, TextOutput)
  assert_true(text.contains("Entries: 1"))
  assert_true(text.contains("Body bytes: 7"))
  let json = store_stats_report(root, JsonOutput)
  assert_true(json.contains("\"entries\": 1"))
  assert_true(json.contains("\"body_bytes\": 7"))
}

///|
test "CLI parses inspect with --store option" {
  assert_true(
    parse_command(["inspect", "--store", "cachedir"])
    is Inspect("cachedir", TextOutput),
  )
  assert_true(
    parse_command(["inspect", "--store", "cachedir", "--json"])
    is Inspect("cachedir", JsonOutput),
  )
}

///|
test "CLI rejects inspect without --store path" {
  let result : Result[CliCommand, CliArgumentError] = Ok(
    parse_command(["inspect"]),
  ) catch {
    error => Err(error)
  }
  assert_true(
    result is Err(CliArgumentError("inspect requires --store <path>")),
  )
}

///|
test "CLI inspect lists cached URIs with variants" {
  let root = "target/mooncache_cli_tests/inspect"
  prepare_cli_store(root, [
    cli_test_entry("https://example.test/a", 100),
    cli_variant_entry("https://example.test/b", "en", 110),
    cli_variant_entry("https://example.test/b", "zh", 120),
  ])
  let text = store_inspect_report(root, TextOutput)
  assert_true(text.contains("Cached URIs: 2"))
  assert_true(text.contains("https://example.test/a"))
  assert_true(text.contains("variants: 2"))
  let json = store_inspect_report(root, JsonOutput)
  assert_true(json.contains("\"cached_uris\": 2"))
  assert_true(json.contains("\"uri\": \"https://example.test/b\""))
  assert_true(json.contains("\"variants\": 2"))
}

///|
test "CLI parses purge with store and uri options" {
  assert_true(
    parse_command([
      "purge", "--store", "cachedir", "--uri", "https://example.test/a",
    ])
    is Purge("cachedir", "https://example.test/a", TextOutput),
  )
  assert_true(
    parse_command([
      "purge", "--store", "cachedir", "--uri", "https://example.test/a", "--json",
    ])
    is Purge("cachedir", "https://example.test/a", JsonOutput),
  )
}

///|
test "CLI rejects purge without required options" {
  let missing_store : Result[CliCommand, CliArgumentError] = Ok(
    parse_command(["purge", "--uri", "https://example.test/a"]),
  ) catch {
    error => Err(error)
  }
  assert_true(
    missing_store is Err(CliArgumentError("purge requires --store <path>")),
  )
  let missing_uri : Result[CliCommand, CliArgumentError] = Ok(
    parse_command(["purge", "--store", "cachedir"]),
  ) catch {
    error => Err(error)
  }
  assert_true(
    missing_uri is Err(CliArgumentError("purge requires --uri <url>")),
  )
}

///|
test "CLI purge removes every variant of one URI" {
  let root = "target/mooncache_cli_tests/purge"
  prepare_cli_store(root, [
    cli_test_entry("https://example.test/a", 100),
    cli_variant_entry("https://example.test/b", "en", 110),
    cli_variant_entry("https://example.test/b", "zh", 120),
  ])
  let text = store_purge_report(root, "https://example.test/b", TextOutput)
  assert_true(text.contains("Purged 2 entries"))
  let json = store_purge_report(root, "https://example.test/b", JsonOutput)
  assert_true(json.contains("\"removed\": 0"))
  let remaining = store_inspect_report(root, TextOutput)
  assert_true(remaining.contains("Cached URIs: 1"))
}

///|
test "CLI parses verify with --store option" {
  assert_true(
    parse_command(["verify", "--store", "cachedir"])
    is Verify("cachedir", TextOutput),
  )
  assert_true(
    parse_command(["verify", "--store", "cachedir", "--json"])
    is Verify("cachedir", JsonOutput),
  )
}

///|
test "CLI rejects verify without --store path" {
  let result : Result[CliCommand, CliArgumentError] = Ok(
    parse_command(["verify"]),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(CliArgumentError("verify requires --store <path>")))
}

///|
test "CLI verify reports healthy recovered store" {
  let root = "target/mooncache_cli_tests/verify"
  prepare_cli_store(root, [cli_test_entry("https://example.test/data", 100)])
  let text = store_verify_report(root, TextOutput)
  assert_true(text.contains("Status: OK"))
  assert_true(text.contains("Loaded entries: 1"))
  let json = store_verify_report(root, JsonOutput)
  assert_true(json.contains("\"status\": \"ok\""))
  assert_true(json.contains("\"loaded_entries\": 1"))
}

///|
test "CLI verify cleans abandoned temp files during recovery" {
  let root = "target/mooncache_cli_tests/verify_temp"
  prepare_cli_store(root, [cli_test_entry("https://example.test/data", 100)])
  @fs.write_string_to_file(
    "target/mooncache_cli_tests/verify_temp/temp/leftover.tmp", "partial",
  )
  let report = store_verify_report(root, TextOutput)
  assert_true(report.contains("Status: OK"))
  assert_true(report.contains("Temp files removed: 1"))
}

///|
test "CLI parses clean with --store option" {
  assert_true(
    parse_command(["clean", "--store", "cachedir"])
    is Clean("cachedir", TextOutput),
  )
  assert_true(
    parse_command(["clean", "--store", "cachedir", "--json"])
    is Clean("cachedir", JsonOutput),
  )
}

///|
test "CLI rejects clean without --store path" {
  let result : Result[CliCommand, CliArgumentError] = Ok(
    parse_command(["clean"]),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(CliArgumentError("clean requires --store <path>")))
}

///|
test "CLI clean purges quarantine leftovers and compacts" {
  let root = "target/mooncache_cli_tests/clean"
  prepare_cli_store(root, [cli_test_entry("https://example.test/data", 100)])
  @fs.write_string_to_file(
    "target/mooncache_cli_tests/clean/quarantine/junk.dat", "corrupt",
  )
  let text = store_clean_report(root, TextOutput)
  assert_true(text.contains("Quarantined files purged: 1"))
  assert_true(text.contains("Compacted entries: "))
  let json_root = "target/mooncache_cli_tests/clean_json"
  prepare_cli_store(json_root, [
    cli_test_entry("https://example.test/data", 100),
  ])
  @fs.write_string_to_file(
    "target/mooncache_cli_tests/clean_json/quarantine/junk.dat", "corrupt",
  )
  let json = store_clean_report(json_root, JsonOutput)
  assert_true(json.contains("\"quarantined_files_purged\": 1"))
  assert_true(json.contains("\"compacted_entries\":"))
}

///|
async test "caching proxy serves repeated requests from cache" {
  let origin_calls = [0]
  @async.with_task_group() <| group => {
    let upstream = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      upstream.run_forever() <| ((request, body, connection) => {
        while body.read_some() is Some(_) {

        }
        origin_calls[0] = origin_calls[0] + 1
        connection.send_response(
          200,
          "OK",
          extra_headers=Map([("Cache-Control", "max-age=60")]),
        )
        if !(request.meth is Head) {
          connection.write_string("origin payload")
        }
      })
    }
    let proxy = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      caching_proxy_loop(proxy, "http://127.0.0.1:\{upstream.addr.port()}", () => {
        @mooncache.MemoryStore::default()
      })
    }
    let proxy_origin = "http://127.0.0.1:\{proxy.addr.port()}"
    let (_, first_body) = @http.get("\{proxy_origin}/data")
    assert_eq(first_body.text(), "origin payload")
    let (_, second_body) = @http.get("\{proxy_origin}/data")
    assert_eq(second_body.text(), "origin payload")
    let (_, missing_body) = @http.get("\{proxy_origin}/missing")
    assert_eq(missing_body.text(), "origin payload")
    assert_eq(origin_calls[0], 2)
  }
}

///|
fn sorted_json_files(directory : String) -> Array[String] raise {
  let names = @fs.read_dir(directory)
  names.sort_by(compare_cli_paths)
  let paths : Array[String] = []
  for name in names {
    if name.to_lower().has_suffix(".json") {
      paths.push(join_path(directory, name))
    }
  }
  paths
}

///|
test "bundled rule scenarios exceed the final-acceptance floor and all pass" {
  let paths = sorted_json_files("testdata/scenarios")
  assert_true(paths.length() >= 250)
  let mut failures = 0
  let first_failures : Array[String] = []
  for path in paths {
    let text = @fs.read_file_to_string(path)
    let analysis = @mooncache.analyze_scenario_json(text) catch {
      error => {
        failures = failures + 1
        if first_failures.length() < 5 {
          first_failures.push("\{path}: parse \{@debug.to_string(error)}")
        }
        continue
      }
    }
    if !analysis.valid {
      failures = failures + 1
      if first_failures.length() < 5 {
        first_failures.push("\{path}: \{analysis.errors.join("; ")}")
      }
    }
  }
  assert_eq(failures, 0)
  assert_eq(first_failures, [])
}

///|
test "behavior compatibility fixtures match documented reference decisions" {
  let paths = sorted_json_files("testdata/compat")
  assert_true(paths.length() >= 10)
  for path in paths {
    let text = @fs.read_file_to_string(path)
    let analysis = @mooncache.analyze_scenario_json(text)
    assert_true(analysis.valid)
  }
}

///|
fn cli_variant_entry(
  uri : String,
  language : String,
  tick : Int64,
) -> @mooncache.StoredEntry {
  let request_headers = @mooncache.HeaderMap::new()
  ignore(request_headers.append("Accept-Language", language))
  let response_headers = @mooncache.HeaderMap::new()
  ignore(response_headers.append("Cache-Control", "max-age=60"))
  ignore(response_headers.append("Vary", "Accept-Language"))
  let request = @mooncache.RequestMeta::new(
    "GET",
    uri,
    request_headers,
    @mooncache.Timestamp::from_seconds(tick),
  )
  let response = @mooncache.ResponseMeta::complete(
    200,
    response_headers,
    @mooncache.Timestamp::from_seconds(tick),
    @mooncache.Timestamp::from_seconds(tick),
  )
  let primary = @mooncache.PrimaryCacheKey::from_request(request).unwrap()
  let variant = @mooncache.build_variant_key(
    request.headers,
    @mooncache.parse_vary(response.headers),
  ).unwrap()
  @mooncache.StoredEntry::new(
    primary,
    variant,
    request,
    response,
    b"payload",
    @mooncache.StoredPolicy::cacheable(
      @mooncache.DeltaSeconds::from_seconds(60),
      false,
    ),
    @mooncache.Timestamp::from_seconds(tick),
  )
}
