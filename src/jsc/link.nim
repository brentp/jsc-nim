## Link configuration for JavaScriptCore.
##
## Default (Linux): a prebuilt, statically-linkable JavaScriptCore from Bun's
## WebKit fork (https://github.com/oven-sh/WebKit) is downloaded once at
## compile time into a cache directory and linked into the program. The
## result can be linked fully statically (``--passL:-static``).
##
## Options (``-d:...``):
##   jscPrefix=<dir>          use an already-fetched tree (see fetch-jsc.sh layout); it is never
##                            downloaded into or modified. also read from the ``JSC_PREFIX`` env var.
##   jscLibc=musl             use the musl build of the prebuilt libraries.
##   jscWebkitVersion=<sha>   override the pinned oven-sh/WebKit autobuild.
##   jscMimallocCommit=<sha>  override the pinned oven-sh/mimalloc commit.
##   jscSystem                link a system JavaScriptCore via pkg-config
##                            (javascriptcoregtk-4.1 or -4.0); dynamic only.
##
## On macOS the system JavaScriptCore.framework is used.

import std/[os, strutils]

const
  jscWebkitVersion* {.strdefine.} = "ed67c459b78a45320c138dbedad0ec89cd77ee8f"
  jscMimallocCommit* {.strdefine.} = "5945551d9ea1e3c83dbf5b198b00a3ec51aee395"
  jscPrefix {.strdefine.} = ""
  jscLibc {.strdefine.} = "glibc"

when defined(macosx):
  const jscBackend* = "framework"
  {.passL: "-framework JavaScriptCore".}

elif defined(jscSystem):
  const jscBackend* = "system"
  const jscPkg = block:
    let r = gorgeEx("pkg-config --exists javascriptcoregtk-4.1")
    if r.exitCode == 0: "javascriptcoregtk-4.1" else: "javascriptcoregtk-4.0"
  {.passL: gorge("pkg-config --libs " & jscPkg).}

else:
  const jscBackend* = "bun-prebuilt"
  const jscArch = when defined(amd64): "amd64"
                  elif defined(arm64): "arm64"
                  else: "unsupported"
  when jscArch == "unsupported":
    {.error: "jsc-nim: prebuilt JavaScriptCore is only available for amd64 and arm64 linux. use -d:jscSystem".}

  proc cacheRoot(): string {.compileTime.} =
    result = getEnv("XDG_CACHE_HOME")
    if result.len == 0:
      result = getEnv("HOME") / ".cache"
    result = result / "jsc-nim"

  const jscManaged = jscPrefix.len == 0 and getEnv("JSC_PREFIX").len == 0
    ## true when jsc-nim owns the directory (the default cache location).

  const jscDir* = block:
    var d = jscPrefix
    if d.len == 0: d = getEnv("JSC_PREFIX")
    if d.len == 0:
      # every input that changes the downloaded tree is part of the key.
      d = cacheRoot() / (jscWebkitVersion[0..11] & "-mi" & jscMimallocCommit[0..7] & "-" & jscArch & "-" & jscLibc)
    d

  const jscFetchScript = currentSourcePath().parentDir / "fetch-jsc.sh"
  # must match what fetch-jsc.sh writes.
  const jscExpectedVersion = "webkit=" & jscWebkitVersion & "\nmimalloc=" & jscMimallocCommit &
                             "\narch=" & jscArch & "\nlibc=" & jscLibc & "\n"

  static:
    let haveLib = fileExists(jscDir / "lib" / "libJavaScriptCore.a")
    let versionFile = jscDir / "VERSION"
    let versionOK = haveLib and fileExists(versionFile) and readFile(versionFile) == jscExpectedVersion
    if not jscManaged:
      # an explicit prefix is the user's directory: never download into (or replace) it.
      if not haveLib:
        raise newException(OSError, "[jsc-nim] " & jscDir / "lib" / "libJavaScriptCore.a" &
          " not found. jscPrefix / JSC_PREFIX must point to a tree made by fetch-jsc.sh;" &
          " unset it to let jsc-nim download into its own cache.")
      if not versionOK:
        echo "[jsc-nim] warning: ", versionFile, " does not match the requested versions:\n", jscExpectedVersion,
             "using it anyway because it was given explicitly (jscPrefix / JSC_PREFIX)"
    elif not versionOK:
      if haveLib:
        echo "[jsc-nim] ", jscDir, " does not match the requested versions; fetching again"
      let cmd = "bash " & quoteShell(jscFetchScript) & " " & quoteShell(jscDir) & " " &
                jscWebkitVersion & " " & jscMimallocCommit & " " & jscArch & " " & jscLibc
      echo "[jsc-nim] downloading JavaScriptCore into ", jscDir, " (one-time, ~260MB)"
      let (output, code) = gorgeEx(cmd)
      if code != 0:
        echo output
        raise newException(OSError, "[jsc-nim] failed to fetch JavaScriptCore. command was:\n" & cmd)
      if readFile(versionFile) != jscExpectedVersion:
        raise newException(OSError, "[jsc-nim] fetched tree in " & jscDir & " has an unexpected VERSION file")

  const miFlags = "-O2 -DMI_STATIC_LIB -DMI_SKIP_COLLECT_ON_EXIT=1 -DMI_NO_PROCESS_DETACH=1" &
                  " -DMI_FREE_USE_PAGEMAP=1 -DMI_BUILD_RELEASE -DMI_DEFAULT_ALLOW_THP=0" &
                  " -DMI_CMAKE_BUILD_TYPE=release -fvisibility=hidden -Wno-deprecated -fPIC" &
                  (if jscLibc == "musl": " -DMI_LIBC_MUSL=1 -ftls-model=local-dynamic" else: " -ftls-model=initial-exec") &
                  " -I" & quoteShell(jscDir / "mimalloc" / "include")

  # mimalloc is used by JSC as its heap allocator (it does *not* replace malloc).
  {.compile(jscDir / "mimalloc" / "src" / "static.c", miFlags).}
  # symbols the Bun fork expects its embedder to provide.
  {.compile: "bunstubs.c".}
  # the typed array functions with the API lock taken (see bunlock.cpp).
  {.compile("bunlock.cpp", "-std=c++17 -O2 -fno-exceptions -I" & quoteShell(jscDir / "include")).}

  const jscLibs = block:
    var s = ""
    for l in ["libJavaScriptCore.a", "libWTF.a", "libbmalloc.a", "libicui18n.a", "libicuuc.a", "libicudata.a"]:
      s.add quoteShell(jscDir / "lib" / l)
      s.add " "
    # ICU's data object lacks a .note.GNU-stack section; without this the linker
    # would mark the whole program as needing an executable stack.
    s & "-lstdc++ -lm -latomic -lpthread -ldl -Wl,-z,noexecstack"
  {.passL: jscLibs.}
