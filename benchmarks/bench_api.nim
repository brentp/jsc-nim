import times, jsc
let c = newJSContext()
let n = 2_000_000
template bench(label: string, body: untyped) =
  block:
    let t = cpuTime()
    for i {.inject.} in 0..<n:
      body
    echo label, ": ", formatFloat((cpuTime() - t) / n.float * 1e9, ffDecimal, 1), " ns/op"
import strutils
let o = c.newObject()
let k = jsName("DP")
c.setGlobal("kid", o)
bench "set property (number)":
  c[o, k] = c.toJS(i)
bench "set global":
  c.setGlobal(k, c.toJS(i))
let noop = c.compileFunction("return true")
bench "call no-op":
  discard c.call(noop)
let rd = c.compileFunction("return kid.DP > 3")
bench "call reading 1 prop":
  discard c.call(rd).toBool(c)
var buf = newSeq[int32](3000)
c.setGlobal("DPA", c.newTypedArray(cast[ptr UncheckedArray[int32]](buf[0].addr), buf.len))
discard c.eval("""
var Sproto = { get DP() { return DPA[this.i] } };
var S = []; for (var j = 0; j < 1000; j++) { var s = Object.create(Sproto); s.i = j; S.push(s) }
var kid = S[0], mom = S[1], dad = S[2];
""")
let rd2 = c.compileFunction("return kid.DP > 3 && mom.DP > 3 && dad.DP < 10")
bench "call reading 3 typed-array getters":
  buf[0] = i.int32; buf[1] = 5; buf[2] = 4
  discard c.call(rd2).toBool(c)
let s = "x".repeat(200)
bench "make 200 char string":
  discard c.toJS(s)
