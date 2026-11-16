import times, jsc, strutils
let c = newJSContext()
var dp = newSeq[int32](300)
var ad = newSeq[int32](600)
var alts = newSeq[int8](300)
c.setGlobal("DPA", c.newTypedArray(cast[ptr UncheckedArray[int32]](dp[0].addr), dp.len))
c.setGlobal("ADA", c.newTypedArray(cast[ptr UncheckedArray[int32]](ad[0].addr), ad.len))
c.setGlobal("ALTS", c.newTypedArray(cast[ptr UncheckedArray[int8]](alts[0].addr), alts.len))
var strs = @["PASS", "LowQual"]
var which = 0
proc vs(ctx: JSContextRef, function: JSObjectRef, thisObject: JSObjectRef, argumentCount: csize_t,
        arguments: ptr UncheckedArray[JSValueRef], exception: ptr JSValueRef): JSValueRef {.cdecl.} =
  ctx.toJS(strs[which])
c.setGlobal("__vs", c.newFunction("__vs", vs))
discard c.eval("""
var FMT_IDX = Object.create(null); FMT_IDX.DP = 0; FMT_IDX.AD = 1; FMT_IDX.alts = 2; FMT_IDX.het = 3; FMT_IDX.hom_ref = 4;
var FMT_N = [1, 2, 1, 1, 1]; var ARR = [DPA, ADA, ALTS];
var H = {
  get(t, p) {
    var f = FMT_IDX[p];
    if (f !== undefined) {
      var i = t.__i;
      switch (f) {
        case 2: return ALTS[i];
        case 3: return ALTS[i] === 1;
        case 4: return ALTS[i] === 0;
      }
      var n = FMT_N[f], a = ARR[f];
      if (n === 1) return a[i];
      var r = new Array(n); for (var k = 0; k < n; k++) r[k] = a[i*n+k]; return r;
    }
    if (p in t) return t[p];
    throw "unknown attribute:" + p;
  },
  has(t, p) { return FMT_IDX[p] !== undefined || p in t }
};
var S = []; for (var j = 0; j < 300; j++) S.push(new Proxy({__i: j, sex: 'male'}, H));
var P = { get DP() { return DPA[this.__i] }, get AD() { var i = this.__i; return [ADA[2*i], ADA[2*i+1]] },
          get het() { return ALTS[this.__i] === 1 }, get hom_ref() { return ALTS[this.__i] === 0 } };
var G = []; for (var j = 0; j < 300; j++) { var o = Object.create(P); o.__i = j; o.sex = 'male'; G.push(o) }
var kid, mom, dad;
function denovo(kid, mom, dad) {
  if (!(kid.het && mom.hom_ref && dad.hom_ref)) return false;
  return kid.DP > 10 && mom.DP > 10 && dad.DP > 10 && (mom.AD[1] + dad.AD[1]) < 2 && kid.sex == 'male';
}
var f = new Function("return denovo(kid, mom, dad)");
var OUT = new Int32Array(1000);
function run(SS) { var m = 0; for (var t = 0; t < 100; t++) { kid = SS[3*t]; dad = SS[3*t+1]; mom = SS[3*t+2]; if (f()) OUT[m++] = t; } return m; }
var vcache = -1, vstr;
var variant = { get FILTER() { return __vs(0) } };
var fexpr = new Function("return variant.FILTER == 'PASS'");
""")
for i in 0..<300:
  dp[i] = int32(i mod 40); ad[2*i] = 10; ad[2*i+1] = int32(i mod 3); alts[i] = int8(i mod 3)
for i in 0..<100: alts[3*i] = 1; alts[3*i+1] = 0; alts[3*i+2] = 0
let n = 20000
for label in ["S", "G"]:
  let fn = c.eval("(function() { return run(" & label & ") })").toObject(c)
  c.protect(fn)
  discard c.call(fn)
  let t = cpuTime()
  var m = 0.0
  for i in 0..<n: m = c.call(fn).toFloat(c)
  echo label, ": ", formatFloat((cpuTime() - t) / (n.float * 100) * 1e9, ffDecimal, 1), " ns per trio-eval of denovo (proxy=S, getters=G) matches=", m
let ff = c.eval("fexpr").toObject(c)
var t = cpuTime()
for i in 0..<n*10: discard c.call(ff).toBool(c)
echo "info expr with native string callback: ", formatFloat((cpuTime() - t) / (n.float*10) * 1e9, ffDecimal, 1), " ns/call"
