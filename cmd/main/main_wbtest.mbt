///|
test "CLI defaults to help" {
  assert_true(parse_command([]) is Help)
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
