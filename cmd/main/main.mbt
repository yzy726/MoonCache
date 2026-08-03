///|
fn usage() -> String {
  let text =
    #|MoonCache 0.1.0
    #|
    #|Usage:
    #|  mooncache explain <scenario.json> [--json]
    #|  mooncache validate <scenario.json>
    #|  mooncache replay <scenario-directory>
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
      second == "help" {
      return raw[1:].to_owned()
    }
  }
  raw
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
fn explain(path : String, json : Bool) -> Unit raise {
  let text = @fs.read_file_to_string(path)
  if json {
    println(@mooncache.explain_scenario_json(text))
  } else {
    println(@mooncache.explain_scenario_text(text))
  }
}

///|
fn validate(path : String) -> Bool raise {
  let text = @fs.read_file_to_string(path)
  let analysis = @mooncache.analyze_scenario_json(text)
  println(@mooncache.validate_scenario_text(text))
  analysis.valid
}

///|
fn replay(directory : String) -> Bool raise {
  let names = @fs.read_dir(directory)
  let mut passed = 0
  let mut failed = 0
  for name in names {
    if name.to_lower().has_suffix(".json") {
      let direct = if @fs.path_exists(name) {
        name
      } else {
        join_path(directory, name)
      }
      let text = @fs.read_file_to_string(direct)
      let analysis = @mooncache.analyze_scenario_json(text)
      if analysis.valid {
        passed = passed + 1
        println("PASS \{analysis.name}: \{analysis.trace.action.label()}")
      } else {
        failed = failed + 1
        println("FAIL \{analysis.name}")
        for error in analysis.errors {
          println("  - \{error}")
        }
      }
    }
  }
  println("Replay summary: \{passed} passed, \{failed} failed")
  failed == 0
}

///|
fn run(args : Array[String]) -> Int raise {
  if args.length() == 0 || args[0] == "help" || args[0] == "--help" {
    println(usage())
    return 0
  }
  if args[0] == "explain" && (args.length() == 2 || args.length() == 3) {
    let json = args.length() == 3 && args[2] == "--json"
    if args.length() == 3 && !json {
      println(usage())
      return 2
    }
    explain(args[1], json)
    return 0
  }
  if args[0] == "validate" && args.length() == 2 {
    return if validate(args[1]) { 0 } else { 1 }
  }
  if args[0] == "replay" && args.length() == 2 {
    return if replay(args[1]) { 0 } else { 1 }
  }
  println(usage())
  2
}

///|
fn main {
  let args = command_args(@sys.get_cli_args())
  let exit_code = run(args) catch {
    error => {
      println("mooncache: \{@debug.to_string(error)}")
      2
    }
  }
  if exit_code != 0 {
    @sys.exit(exit_code)
  }
}
