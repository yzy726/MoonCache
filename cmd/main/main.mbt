///|
priv enum OutputFormat {
  TextOutput
  JsonOutput
}

///|
priv enum CliCommand {
  Explain(String, OutputFormat)
  Validate(String, OutputFormat)
  Replay(String, OutputFormat)
  Help
  Version
}

///|
priv suberror CliArgumentError {
  CliArgumentError(String)
}

///|
fn usage() -> String {
  let text =
    #|MoonCache 0.1.0
    #|
    #|Usage:
    #|  mooncache explain <scenario.json> [--json]
    #|  mooncache validate <scenario.json> [--json]
    #|  mooncache replay <scenario-directory> [--json]
    #|  mooncache --version
    #|
    #|Exit codes:
    #|  0  command succeeded and every expectation matched
    #|  1  a valid scenario did not match its expectation
    #|  2  invalid arguments, unreadable input, or malformed JSON
    #|
    #|All commands are deterministic and perform no network requests.
  text
}

///|
fn command_args(raw : Array[String]) -> Array[String] {
  if raw.length() >= 2 {
    let second = raw[1]
    if second == "explain" ||
      second == "validate" ||
      second == "replay" ||
      second == "help" ||
      second == "version" ||
      second == "--help" ||
      second == "--version" {
      return raw[1:].to_owned()
    }
  }
  raw
}

///|
fn output_format(args : Array[String]) -> OutputFormat raise CliArgumentError {
  match args.length() {
    2 => TextOutput
    3 =>
      if args[2] == "--json" {
        JsonOutput
      } else {
        raise CliArgumentError("unknown option: \{args[2]}")
      }
    _ => raise CliArgumentError("wrong number of arguments")
  }
}

///|
fn parse_command(args : Array[String]) -> CliCommand raise CliArgumentError {
  guard args.length() > 0 else { return Help }
  match args[0] {
    "help" | "--help" => {
      guard args.length() == 1 else {
        raise CliArgumentError("help accepts no arguments")
      }
      Help
    }
    "version" | "--version" => {
      guard args.length() == 1 else {
        raise CliArgumentError("version accepts no arguments")
      }
      Version
    }
    "explain" => {
      guard args.length() >= 2 else {
        raise CliArgumentError("explain requires a scenario path")
      }
      Explain(args[1], output_format(args))
    }
    "validate" => {
      guard args.length() >= 2 else {
        raise CliArgumentError("validate requires a scenario path")
      }
      Validate(args[1], output_format(args))
    }
    "replay" => {
      guard args.length() >= 2 else {
        raise CliArgumentError("replay requires a scenario directory")
      }
      Replay(args[1], output_format(args))
    }
    command => raise CliArgumentError("unknown command: \{command}")
  }
}

///|
fn join_path(directory : String, name : String) -> String {
  if directory.has_suffix("/") || directory.has_suffix("\\") {
    "\{directory}\{name}"
  } else {
    "\{directory}/\{name}"
  }
}

///|
fn resolve_directory_entry(directory : String, name : String) -> String {
  if @fs.path_exists(name) {
    name
  } else {
    join_path(directory, name)
  }
}

///|
fn compare_cli_paths(left : String, right : String) -> Int {
  let limit = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index = 0; index < limit; index = index + 1 {
    let left_unit = left.code_unit_at(index)
    let right_unit = right.code_unit_at(index)
    if left_unit < right_unit {
      return -1
    }
    if left_unit > right_unit {
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
fn explain(path : String, format : OutputFormat) -> Unit raise {
  let text = @fs.read_file_to_string(path)
  match format {
    JsonOutput => println(@mooncache.explain_scenario_json(text))
    TextOutput => println(@mooncache.explain_scenario_text(text))
  }
}

///|
fn validation_json(analysis : @mooncache.ScenarioAnalysis) -> String {
  Json::object({
    "name": analysis.name,
    "valid": analysis.valid,
    "errors": Json::array(
      analysis.errors.map(fn(error) { Json::string(error) }),
    ),
  }).stringify(indent=2)
}

///|
fn validate(path : String, format : OutputFormat) -> Bool raise {
  let text = @fs.read_file_to_string(path)
  let analysis = @mooncache.analyze_scenario_json(text)
  match format {
    JsonOutput => println(validation_json(analysis))
    TextOutput => println(@mooncache.validate_scenario_text(text))
  }
  analysis.valid
}

///|
priv struct ReplayCase {
  file : String
  name : String
  action : String?
  valid : Bool
  errors : Array[String]
}

///|
fn ReplayCase::to_json(self : ReplayCase) -> Json {
  let object : Map[String, Json] = {
    "file": self.file,
    "name": self.name,
    "valid": self.valid,
    "errors": Json::array(self.errors.map(fn(error) { Json::string(error) })),
  }
  match self.action {
    Some(action) => object["action"] = Json::string(action)
    None => ()
  }
  Json::object(object)
}

///|
fn read_replay_case(path : String) -> ReplayCase {
  try {
    let text = @fs.read_file_to_string(path)
    let analysis = @mooncache.analyze_scenario_json(text)
    ReplayCase::{
      file: path,
      name: analysis.name,
      action: Some(analysis.trace.action.label()),
      valid: analysis.valid,
      errors: analysis.errors.copy(),
    }
  } catch {
    error =>
      ReplayCase::{
        file: path,
        name: path,
        action: None,
        valid: false,
        errors: [@debug.to_string(error)],
      }
  }
}

///|
fn print_replay_case(result : ReplayCase) -> Unit {
  if result.valid {
    let action = result.action.unwrap_or("UNKNOWN")
    println("PASS \{result.name}: \{action}")
  } else {
    println("FAIL \{result.name}")
    for error in result.errors {
      println("  - \{error}")
    }
  }
}

///|
fn replay_json(
  directory : String,
  results : Array[ReplayCase],
  passed : Int,
  failed : Int,
) -> String {
  Json::object({
    "directory": directory,
    "passed": passed,
    "failed": failed,
    "valid": failed == 0 && results.length() > 0,
    "cases": Json::array(results.map(fn(result) { result.to_json() })),
  }).stringify(indent=2)
}

///|
fn replay(directory : String, format : OutputFormat) -> Bool raise {
  let names = @fs.read_dir(directory)
  names.sort_by(compare_cli_paths)
  let results : Array[ReplayCase] = []
  let mut passed = 0
  let mut failed = 0
  for name in names {
    if name.to_lower().has_suffix(".json") {
      let path = resolve_directory_entry(directory, name)
      let result = read_replay_case(path)
      results.push(result)
      if result.valid {
        passed = passed + 1
      } else {
        failed = failed + 1
      }
      if format is TextOutput {
        print_replay_case(result)
      }
    }
  }
  if results.length() == 0 {
    failed = failed + 1
    if format is TextOutput {
      println("FAIL no JSON scenario files found in \{directory}")
    }
  }
  match format {
    JsonOutput => println(replay_json(directory, results, passed, failed))
    TextOutput => println("Replay summary: \{passed} passed, \{failed} failed")
  }
  failed == 0
}

///|
fn run(args : Array[String]) -> Int raise {
  match parse_command(args) {
    Help => {
      println(usage())
      0
    }
    Version => {
      println("mooncache 0.1.0")
      0
    }
    Explain(path, format) => {
      explain(path, format)
      0
    }
    Validate(path, format) => if validate(path, format) { 0 } else { 1 }
    Replay(directory, format) => if replay(directory, format) { 0 } else { 1 }
  }
}

///|
fn main {
  let args = command_args(@sys.get_cli_args())
  let exit_code = run(args) catch {
    CliArgumentError(message) => {
      println("mooncache: \{message}")
      println(usage())
      2
    }
    error => {
      println("mooncache: \{@debug.to_string(error)}")
      2
    }
  }
  if exit_code != 0 {
    @sys.exit(exit_code)
  }
}
