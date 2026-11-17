# Package

version       = "0.1.3"
author        = "Brent Pedersen"
description   = "Nim bindings for JavaScriptCore, with a statically-linkable prebuilt engine on linux"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim", "sh", "c", "cpp"]

# Dependencies

requires "nim >= 1.6.0"

task test, "run the tests":
  exec "nim c -d:release -r tests/test_jsc.nim"

task bench, "run micro-benchmarks of the C API":
  exec "nim c -d:release -r benchmarks/bench_api.nim"
