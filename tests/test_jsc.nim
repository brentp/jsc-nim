import unittest, strutils, times
import jsc

let c = newJSContext()

suite "jsc":
  test "eval numbers":
    check c.eval("1 + 2").toFloat(c) == 3.0
    check c.eval("let q = 0; for (let i = 0; i < 1000; i++) q += i; q").toFloat(c) == 499500.0

  test "globals and strings":
    c.setGlobal("greeting", "hello")
    check c.eval("greeting + ' world'").toString(c) == "hello world"
    c.setGlobal("n", 22.5)
    check c.eval("n * 2").toFloat(c) == 45.0
    c.setGlobal("arr", @[1, 2, 3])
    check c.eval("arr.reduce((a, b) => a + b)").toFloat(c) == 6.0
    c.setGlobal("names", @["a", "b"])
    check c.eval("names.join(',')").toString(c) == "a,b"

  test "objects":
    let o = c.newObject()
    c.setProp(o, "x", 3)
    c.setProp(o, "flag", true)
    c.setGlobal("obj", o)
    check c.eval("obj.x == 3 && obj.flag").toBool(c)
    check c.hasProp(o, "x")
    c.delProp(o, "x")
    check not c.hasProp(o, "x")
    check c.toJSON(o) == """{"flag":true}"""

  test "errors raise JSError":
    expect JSError:
      discard c.eval("throw new Error('boom')")
    try:
      discard c.eval("undefinedThing.foo")
    except JSError as e:
      check "undefinedThing" in e.msg
    check c.checkSyntax("a +") != ""
    check c.checkSyntax("a + 1") == ""

  test "compiled functions":
    let f = c.compileFunction("return a.DP > 10 && b < 3", ["a", "b"])
    let o = c.newObject()
    c.setProp(o, "DP", 20)
    check c.call(f, [JSValueRef(o), c.toJS(1)]).toBool(c)
    check not c.call(f, [JSValueRef(o), c.toJS(5)]).toBool(c)

  test "native function":
    proc add(ctx: JSContextRef, function: JSObjectRef, thisObject: JSObjectRef, argumentCount: csize_t,
             arguments: ptr UncheckedArray[JSValueRef], exception: ptr JSValueRef): JSValueRef {.cdecl.} =
      # callbacks must not raise: use the C API directly and report errors via `exception`.
      var s = 0.0
      for i in 0..<argumentCount.int:
        s += JSValueToNumber(ctx, arguments[i], exception).float
        if exception[] != nil: return nil
      ctx.toJS(s)
    c.setGlobal("add", c.newFunction("add", add))
    check c.eval("add(1, 2, 3.5)").toFloat(c) == 6.5

  test "typed array views nim memory":
    var data = newSeq[int32](4)
    c.setGlobal("ta", c.newTypedArray(cast[ptr UncheckedArray[int32]](data[0].addr), data.len))
    data[2] = 42
    check c.eval("ta[2]").toFloat(c) == 42.0
    discard c.eval("ta[1] = 7")
    check data[1] == 7

  test "property names":
    let o = c.eval("({a: 1, b: 2})").toObject(c)
    check c.propertyNames(o) == @["a", "b"]

  test "second context is independent":
    let c2 = newJSContext()
    c2.setGlobal("only2", 1)
    check c.eval("typeof only2").toString(c) == "undefined"
    check c2.eval("typeof only2").toString(c2) == "number"

  test "array conversion keeps temporaries alive under GC pressure":
    var big = newSeq[string](500_000)
    for i in 0..<big.len: big[i] = "s" & $i & "xxxxxxxxxxxxxxxxxxxx"
    c.setGlobal("big", big)
    check c.eval("big.length === 500000 && big.every((s, i) => s === 's' + i + 'xxxxxxxxxxxxxxxxxxxx')").toBool(c)
    discard c.eval("big = null")

  test "typedArrayData honors the byte offset":
    let sub = c.eval("globalThis.u8 = new Uint8Array([10, 20, 30]); u8.subarray(1)").toObject(c)
    let p = cast[ptr UncheckedArray[uint8]](c.typedArrayData(sub))
    check c.typedArrayLen(sub) == 2
    check p[0] == 20
    check p[1] == 30
    p[0] = 21
    check c.eval("u8[1]").toFloat(c) == 21.0

  test "embedded NUL bytes are preserved":
    c.setGlobal("nul", "a\0b")
    check c.eval("nul.length").toFloat(c) == 3.0
    check c.eval("nul.charCodeAt(1)").toFloat(c) == 0.0
    check c.getGlobal("nul").toString(c) == "a\0b"
    let o = c.newObject()
    c.setProp(o, "a\0b", 1)
    check not c.hasProp(o, "a")
    check c.hasProp(o, "a\0b")
    expect JSError:
      discard c.eval("1\0; throw new Error('after nul')")
    check c.toJSON(c.toJS(@["x\0y"])) == "[\"x\\u0000y\"]"

  test "utf-8 round trip and invalid utf-8":
    c.setGlobal("u", "héllo 🧬")
    check c.eval("u.length").toFloat(c) == 8.0  # "héllo " is 6, the emoji is a surrogate pair
    check c.getGlobal("u").toString(c) == "héllo 🧬"
    c.setGlobal("bad", "a\xffb")
    check c.eval("bad").toString(c) == "a\uFFFDb"

  test "toString raises when conversion throws; toStringSafe does not":
    let v = c.eval("({toString() { throw new Error('nope') }})")
    expect JSError:
      discard v.toString(c)
    check "nope" in v.toStringSafe(c)
    check "nope" in c.errorMessage(v)

  test "out of range indexes are rejected":
    let a = c.newArray([])
    expect IndexDefect:
      c[a, -1] = c.toJS(1)
    expect IndexDefect:
      discard c[a, int(uint32.high) + 1]
    check c.propertyNames(a).len == 0
    c[a, 2] = c.toJS(5)
    check c[a, 2].toFloat(c) == 5.0

  test "contexts can be closed; private VMs work":
    for i in 0..<20:
      let t = newJSContext()
      check t.eval("[1,2,3].map(x => x * 2).join()").toString(t) == "2,4,6"
      t.close()
    for i in 0..<5:
      let t = newJSContext(shared = false)
      check t.eval("let s = 0; for (let k = 0; k < 1e5; k++) s += k; s").toFloat(t) == 4999950000.0
      t.close()
    let n = jsName("tmp")
    check $n == "tmp"
    n.release()

  test "unpaired surrogates become U+FFFD instead of truncating":
    check c.eval("'before\\uD800after'").toString(c) == "before\uFFFDafter"
    check c.eval("'x\\uDC00y'").toString(c) == "x\uFFFDy"
    check c.eval("'pair \\uD83E\\uDDEC ok'").toString(c) == "pair 🧬 ok"
    check c.eval("'a\\u0000b'").toString(c) == "a\0b"

  test "calling a non-function raises":
    expect JSError:
      discard c.call(c.newObject())

  test "invalid typed array arguments raise":
    var buf = newSeq[int32](4)
    let p = cast[ptr UncheckedArray[int32]](buf[0].addr)
    expect ValueError:
      discard c.newTypedArray(p, -1)
    expect ValueError:
      discard c.newTypedArray(p, high(int) div 2)
    expect ValueError:
      discard c.newTypedArrayNoCopy(kJSTypedArrayTypeNone, p, 16)
    expect ValueError:
      discard c.newTypedArrayNoCopy(kJSTypedArrayTypeInt32Array, nil, 16)
    check c.typedArrayLen(c.newTypedArray(p, 0)) == 0

  test "speed: compiled call":
    let f = c.compileFunction("return kid.DP < 500 && dad > 21 && mom == kid.DP")
    let kid = c.newObject()
    c.setGlobal("kid", kid)
    let dp = jsName("DP")
    let mom = jsName("mom")
    let dad = jsName("dad")
    when defined(release):
      let tries = 2_000_000
    else:
      let tries = 100_000
    var t = cpuTime()
    var success = 0
    for i in 0..<tries:
      c[kid, dp] = c.toJS(i)
      c.setGlobal(mom, c.toJS(i))
      c.setGlobal(dad, c.toJS(23))
      if c.call(f).toBool(c):
        success.inc
    check success == 500
    echo "  ", (cpuTime() - t) / (tries / 1_000_000), " seconds per million evaluations (3 sets + call)"
