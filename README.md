# jsc-nim

Nim bindings for [JavaScriptCore](https://docs.webkit.org/Deep%20Dive/JSC/JavaScriptCore.html) (JSC), the JIT-compiling
JavaScript engine from WebKit, with an easy, statically-linkable build on linux.

```nim
import jsc

let ctx = newJSContext()
ctx.setGlobal("x", 41)
echo ctx.eval("x + 1").toFloat(ctx)        # 42.0

# compile once, call many times
let f = ctx.compileFunction("return s.DP > 10 && n < 3", ["s", "n"])
echo ctx.call(f, [ctx.eval("({DP: 20})"), ctx.toJS(1)]).toBool(ctx)   # true

# share nim memory with javascript (no copies)
var data = newSeq[int32](1000)
ctx.setGlobal("DP", ctx.newTypedArray(cast[ptr UncheckedArray[int32]](data[0].addr), data.len))
data[3] = 22
echo ctx.eval("DP[3]").toFloat(ctx)        # 22.0
```

`jsc/raw` has the complete public C API (`JavaScriptCore/JavaScript.h`). `jsc` adds a thin layer over it:
contexts, evaluation and compiled functions that raise `JSError`, conversions, properties, native
callbacks and typed arrays.

## Building

There is nothing to install. On linux (x86_64 and aarch64), the first compile downloads a prebuilt JSC
from [Bun's WebKit fork](https://github.com/oven-sh/WebKit) (~260MB, pinned to the version Bun uses),
strips its debug info, and caches it (~130MB) in `~/.cache/jsc-nim/`. The engine is linked statically,
so programs can be built as fully static binaries:

```
nim c -d:release --passL:-static myprog.nim
```

The engine adds about 50MB to a binary.

Options (`-d:...`):

| define | effect |
|---|---|
| `jscPrefix=<dir>` | use an already-fetched tree (also: `JSC_PREFIX` env var at compile time) |
| `jscLibc=musl` | use the musl build (for alpine / musl static builds) |
| `jscWebkitVersion=<sha>` | use another `oven-sh/WebKit` autobuild |
| `jscSystem` | link the system `javascriptcoregtk` via pkg-config (dynamic) |

For offline builds, download the tarballs elsewhere and point `JSC_WEBKIT_TARBALL` and
`JSC_MIMALLOC_TARBALL` at them (see `src/jsc/fetch-jsc.sh`).

On macOS the system `JavaScriptCore.framework` is used.

### Notes

+ Bun's JSC uses mimalloc for the JS heap; jsc-nim compiles the matching mimalloc commit into your
  program (it does not replace `malloc`). It also provides the few symbols the Bun fork expects
  from its embedder (`src/jsc/bunstubs.c`).
+ All contexts share one VM (context group). Contexts are not released: JSC's VM teardown asserts in
  this build, so programs should create the contexts they need and simply exit.

## Performance

Calls through the C API cost roughly 150-350ns each (see `nimble bench`), while JIT-compiled JavaScript
runs at native-like speed. For hot loops, share data through typed arrays and make one call into
JavaScript that does many evaluations, rather than setting many properties from nim.
