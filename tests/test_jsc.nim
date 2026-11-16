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
      var s = 0.0
      for i in 0..<argumentCount.int:
        s += arguments[i].toFloat(ctx)
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
