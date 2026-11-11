// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "Ag108/MoonCache"

version = "0.3.0"

readme = "README.mbt.md"

repository = "https://github.com/yzy726/MoonCache"

license = "Apache-2.0"

keywords = [ "http", "cache", "rfc9111" ]

preferred_target = "native"

description = "A transport-independent, explainable HTTP cache policy and runtime toolkit."

import {
  "moonbitlang/x@0.5.7",
  "moonbitlang/async@0.22.9",
  "f4ah6o/http11@0.1.2",
}
