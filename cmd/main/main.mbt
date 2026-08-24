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
  Stats(String, OutputFormat)
  Inspect(String, OutputFormat)
  Purge(String, String, OutputFormat)
  Verify(String, OutputFormat)
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
    #|MoonCache 0.2.0
    #|
    #|Usage:
    #|  mooncache explain <scenario.json> [--json]
    #|  mooncache validate <scenario.json> [--json]
    #|  mooncache replay <scenario-directory> [--json]
    #|  mooncache stats --store <dir> [--json]
    #|  mooncache inspect --store <dir> [--json]
    #|  mooncache purge --store <dir> --uri <url> [--json]
    #|  mooncache verify --store <dir> [--json]
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
  if raw.length() == 0 {
    return []
  }
  raw[1:].to_owned()
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
priv struct StoreCommandOptions {
  mut store : String?
  mut uri : String?
  mut format : OutputFormat
}

///|
fn parse_store_options(
  args : Array[String],
) -> StoreCommandOptions raise CliArgumentError {
  let options = StoreCommandOptions::{
    store: None,
    uri: None,
    format: TextOutput,
  }
  let mut index = 1
  while index < args.length() {
    match args[index] {
      "--store" => {
        guard index + 1 < args.length() else {
          raise CliArgumentError("--store requires a directory path")
        }
        options.store = Some(args[index + 1])
        index = index + 2
      }
      "--uri" => {
        guard index + 1 < args.length() else {
          raise CliArgumentError("--uri requires a URI value")
        }
        options.uri = Some(args[index + 1])
        index = index + 2
      }
      "--json" => {
        options.format = JsonOutput
        index = index + 1
      }
      token => raise CliArgumentError("unknown option: \{token}")
    }
  }
  options
}

///|
fn require_store_path(
  command : String,
  options : StoreCommandOptions,
) -> String raise CliArgumentError {
  match options.store {
    Some(path) => path
    None => raise CliArgumentError("\{command} requires --store <path>")
  }
}

///|
fn require_uri_value(
  command : String,
  options : StoreCommandOptions,
) -> String raise CliArgumentError {
  match options.uri {
    Some(uri) => uri
    None => raise CliArgumentError("\{command} requires --uri <url>")
  }
}

///|
fn open_cli_store(
  path : String,
) -> @file_store.FileStore raise CliArgumentError {
  @file_store.FileStore::open(path) catch {
    error => raise CliArgumentError(@file_store.FileStoreError::message(error))
  }
}

///|
fn store_stats_report(path : String, format : OutputFormat) -> String raise {
  let store = open_cli_store(path)
  match format {
    JsonOutput => store.stats().json_report()
    TextOutput => store.stats().text_report()
  }
}

///|
priv struct InspectItem {
  uri : String
  variants : Int
  body_bytes : Int64
}

///|
fn json_int64(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn InspectItem::to_json(self : InspectItem) -> Json {
  Json::object({
    "uri": Json::string(self.uri),
    "variants": self.variants,
    "body_bytes": json_int64(self.body_bytes),
  })
}

///|
fn collect_inspect_items(store : @file_store.FileStore) -> Array[InspectItem] {
  let uris = store.cached_uris()
  uris.sort_by(compare_cli_paths)
  uris.map(fn(uri) {
    let variants = store.peek_variants(uri)
    let mut body_bytes : Int64 = 0L
    for entry in variants {
      body_bytes = body_bytes + entry.body_size()
    }
    InspectItem::{ uri, variants: variants.length(), body_bytes }
  })
}

///|
fn inspect_json(items : Array[InspectItem]) -> String {
  let mut entries = 0
  for item in items {
    entries = entries + item.variants
  }
  Json::object({
    "cached_uris": items.length(),
    "entries": entries,
    "items": Json::array(items.map(fn(item) { item.to_json() })),
  }).stringify(indent=2)
}

///|
fn inspect_text(items : Array[InspectItem]) -> String {
  let body : Array[String] = []
  let mut entries = 0
  for item in items {
    entries = entries + item.variants
    body.push(item.uri)
    body.push("  variants: \{item.variants}")
    body.push("  body bytes: \{item.body_bytes}")
  }
  let header : Array[String] = [
    "Cached URIs: \{items.length()}",
    "Entries: \{entries}",
  ]
  header.append(body)
  header.join("\n")
}

///|
fn store_inspect_report(path : String, format : OutputFormat) -> String raise {
  let store = open_cli_store(path)
  let items = collect_inspect_items(store)
  match format {
    JsonOutput => inspect_json(items)
    TextOutput => inspect_text(items)
  }
}

///|
fn store_purge_report(
  path : String,
  uri : String,
  format : OutputFormat,
) -> String raise {
  let store = open_cli_store(path)
  let removed = store.invalidate_uri(uri)
  match format {
    JsonOutput =>
      Json::object({ "uri": Json::string(uri), "removed": removed }).stringify(
        indent=2,
      )
    TextOutput => "Purged \{removed} entries for \{uri}"
  }
}

///|
fn verify_status(store : @file_store.FileStore) -> String {
  if store.last_error() is None {
    "OK"
  } else {
    "DEGRADED"
  }
}

///|
fn verify_json(
  path : String,
  store : @file_store.FileStore,
  status : String,
) -> String {
  let recovery = store.recovery_report()
  Json::object({
    "store": Json::string(path),
    "status": Json::string(status.to_lower()),
    "recovery": Json::object({
      "loaded_entries": recovery.loaded_entries,
      "quarantined_entries": recovery.quarantined_entries,
      "dropped_entries": recovery.dropped_entries,
      "temp_files_removed": recovery.temp_files_removed,
      "orphan_files_removed": recovery.orphan_files_removed,
      "indexes_rebuilt": recovery.indexes_rebuilt,
      "manifest_rebuilt": recovery.manifest_rebuilt,
    }),
  }).stringify(indent=2)
}

///|
fn verify_text(
  path : String,
  store : @file_store.FileStore,
  status : String,
) -> String {
  let recovery = store.recovery_report()
  let lines = [
    "Store: \{path}",
    "Status: \{status}",
    "Loaded entries: \{recovery.loaded_entries}",
    "Quarantined entries: \{recovery.quarantined_entries}",
    "Dropped entries: \{recovery.dropped_entries}",
    "Temp files removed: \{recovery.temp_files_removed}",
    "Orphan files removed: \{recovery.orphan_files_removed}",
    "Indexes rebuilt: \{recovery.indexes_rebuilt}",
    "Manifest rebuilt: \{recovery.manifest_rebuilt}",
  ]
  match store.last_error() {
    Some(message) => lines.push("Last error: \{message}")
    None => ()
  }
  lines.join("\n")
}

///|
fn store_verify_report(path : String, format : OutputFormat) -> String raise {
  let store = open_cli_store(path)
  let status = verify_status(store)
  match format {
    JsonOutput => verify_json(path, store, status)
    TextOutput => verify_text(path, store, status)
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
    "stats" => {
      let options = parse_store_options(args)
      Stats(require_store_path("stats", options), options.format)
    }
    "inspect" => {
      let options = parse_store_options(args)
      Inspect(require_store_path("inspect", options), options.format)
    }
    "purge" => {
      let options = parse_store_options(args)
      Purge(
        require_store_path("purge", options),
        require_uri_value("purge", options),
        options.format,
      )
    }
    "verify" => {
      let options = parse_store_options(args)
      Verify(require_store_path("verify", options), options.format)
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
      println("mooncache 0.2.0")
      0
    }
    Explain(path, format) => {
      explain(path, format)
      0
    }
    Validate(path, format) => if validate(path, format) { 0 } else { 1 }
    Replay(directory, format) => if replay(directory, format) { 0 } else { 1 }
    Stats(path, format) => {
      println(store_stats_report(path, format))
      0
    }
    Inspect(path, format) => {
      println(store_inspect_report(path, format))
      0
    }
    Purge(path, uri, format) => {
      println(store_purge_report(path, uri, format))
      0
    }
    Verify(path, format) => {
      println(store_verify_report(path, format))
      0
    }
  }
}

///|
extern "C" fn process_exit(code : Int) = "exit"

///|
fn main {
  let args = command_args(@env.args())
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
    process_exit(exit_code)
  }
}
