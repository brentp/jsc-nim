## Nim bindings for JavaScriptCore.
##
## `jsc/raw` has the C API as-is. This module adds a thin, low-overhead layer:
##
## .. code-block:: nim
##   import jsc
##   let ctx = newJSContext()
##   ctx.setGlobal("x", ctx.toJS(41.0))
##   echo ctx.eval("x + 1").toFloat(ctx)      # 42.0
##
##   # compile once, call many times (this is the fast path)
##   let f = ctx.compileFunction("return a.DP > 10 && b < 3", ["a", "b"])
##   echo ctx.call(f, [ctx.eval("({DP: 20})"), ctx.toJS(1)]).toBool(ctx)
##
## Memory management
## -----------------
## JSC's garbage collector finds `JSValueRef`/`JSObjectRef` values that are in
## local variables (it scans the C stack and registers) but **not** values kept in
## Nim heap memory (a `seq`, a `ref object`, a global). Use `protect`/`unprotect`
## for values that are stored in the heap and must survive allocations in JS.
##
## Contexts and threads
## --------------------
## By default every context is created in one shared context group (one VM).
## Contexts in a group can share values, but the VM executes one thread at a
## time (JSC takes a lock on every API call). Use `newJSContext(shared = false)`
## for a context with its own VM, which can run in parallel with other VMs on
## other threads. Values must never be passed between VMs. `close` releases a
## context (and its VM when it has its own).

import std/locks
import ./jsc/raw
export raw

type
  JSError* = object of CatchableError
    ## raised when evaluating JavaScript throws.

  JSContext* = ref object
    ctx*: JSGlobalContextRef
    global*: JSObjectRef
    ownGroup: JSContextGroupRef

  JSName* = distinct JSStringRef
    ## a retained property name. Create these once and reuse them;
    ## call `release` when it is no longer needed.

var defaultGroup: JSContextGroupRef
var defaultGroupLock: Lock
initLock(defaultGroupLock)

proc newJSContext*(shared = true): JSContext =
  ## create a new global context. With `shared` (the default), all contexts
  ## share a single VM; otherwise the context gets its own VM.
  var group: JSContextGroupRef
  if shared:
    withLock defaultGroupLock:
      if defaultGroup == nil:
        defaultGroup = JSContextGroupCreate()
      group = defaultGroup
    result = JSContext(ctx: JSGlobalContextCreateInGroup(group, nil))
  else:
    group = JSContextGroupCreate()
    result = JSContext(ctx: JSGlobalContextCreateInGroup(group, nil), ownGroup: group)
  result.global = JSContextGetGlobalObject(result.ctx)

proc close*(c: JSContext) =
  ## release the context (and its VM if it was created with `shared = false`).
  ## No value from the context may be used afterwards.
  if c == nil or c.ctx == nil: return
  JSGlobalContextRelease(c.ctx)
  c.ctx = nil
  c.global = nil
  if c.ownGroup != nil:
    JSContextGroupRelease(c.ownGroup)
    c.ownGroup = nil

converter toContextRef*(c: JSContext): JSContextRef {.inline.} = c.ctx

# ---------------------------------------------------------------- strings

proc c_memchr(s: pointer, c: cint, n: csize_t): pointer {.importc: "memchr", header: "<string.h>".}

proc utf8ToUtf16(s: string): seq[uint16] =
  ## decode utf-8 (invalid sequences become U+FFFD) to utf-16.
  result = newSeqOfCap[uint16](s.len)
  var i = 0
  let n = s.len
  template cont(k: int): int =
    (if i + k < n and (s[i + k].uint8 and 0xC0) == 0x80: int(s[i + k].uint8 and 0x3F) else: -1)
  while i < n:
    let b = s[i].uint8.int
    var cp = 0xFFFD
    var used = 1
    if b < 0x80:
      cp = b
    elif b >= 0xC2 and b <= 0xDF:
      let c1 = cont(1)
      if c1 >= 0: cp = ((b and 0x1F) shl 6) or c1; used = 2
    elif b >= 0xE0 and b <= 0xEF:
      let c1 = cont(1)
      let c2 = cont(2)
      if c1 >= 0 and c2 >= 0:
        let v = ((b and 0x0F) shl 12) or (c1 shl 6) or c2
        if v >= 0x800 and (v < 0xD800 or v > 0xDFFF): cp = v; used = 3
    elif b >= 0xF0 and b <= 0xF4:
      let c1 = cont(1)
      let c2 = cont(2)
      let c3 = cont(3)
      if c1 >= 0 and c2 >= 0 and c3 >= 0:
        let v = ((b and 0x07) shl 18) or (c1 shl 12) or (c2 shl 6) or c3
        if v >= 0x10000 and v <= 0x10FFFF: cp = v; used = 4
    i += used
    if cp < 0x10000:
      result.add cp.uint16
    else:
      let v = cp - 0x10000
      result.add uint16(0xD800 + (v shr 10))
      result.add uint16(0xDC00 + (v and 0x3FF))

proc newJSString*(s: string): JSStringRef =
  ## create a JSStringRef from a (utf-8) Nim string. The whole string is used,
  ## including embedded NUL bytes; invalid utf-8 becomes U+FFFD.
  ## The caller must `JSStringRelease` the result.
  if s.len == 0:
    return JSStringCreateWithUTF8CString("")
  if c_memchr(s[0].unsafeAddr, 0, s.len.csize_t) == nil:
    result = JSStringCreateWithUTF8CString(s.cstring)
    # JSC returns an empty string for invalid utf-8; fall back to the slow path.
    if JSStringGetLength(result) != 0:
      return
    JSStringRelease(result)
  let u = utf8ToUtf16(s)
  result = JSStringCreateWithCharacters(u[0].unsafeAddr, u.len.csize_t)

proc `$`*(s: JSStringRef): string =
  ## copy a JSStringRef to a Nim string (UTF-8). Embedded NULs are preserved;
  ## unpaired UTF-16 surrogates (legal in javascript strings) become U+FFFD.
  if s == nil: return ""
  let n = JSStringGetLength(s).int
  if n == 0: return ""
  let u = JSStringGetCharactersPtr(s)
  result = newStringOfCap(n)
  var i = 0
  while i < n:
    var cp = u[i].int
    inc i
    if cp >= 0xD800 and cp <= 0xDBFF:
      if i < n and u[i].int >= 0xDC00 and u[i].int <= 0xDFFF:
        cp = 0x10000 + ((cp - 0xD800) shl 10) + (u[i].int - 0xDC00)
        inc i
      else:
        cp = 0xFFFD
    elif cp >= 0xDC00 and cp <= 0xDFFF:
      cp = 0xFFFD
    if cp < 0x80:
      result.add char(cp)
    elif cp < 0x800:
      result.add char(0xC0 or (cp shr 6))
      result.add char(0x80 or (cp and 0x3F))
    elif cp < 0x10000:
      result.add char(0xE0 or (cp shr 12))
      result.add char(0x80 or ((cp shr 6) and 0x3F))
      result.add char(0x80 or (cp and 0x3F))
    else:
      result.add char(0xF0 or (cp shr 18))
      result.add char(0x80 or ((cp shr 12) and 0x3F))
      result.add char(0x80 or ((cp shr 6) and 0x3F))
      result.add char(0x80 or (cp and 0x3F))

template withJSString*(name: untyped, s: string, body: untyped) =
  ## create a temporary JSStringRef `name` from `s` for the duration of body.
  let name = newJSString(s)
  try:
    body
  finally:
    JSStringRelease(name)

proc jsName*(s: string): JSName =
  ## create a reusable property name.
  JSName(newJSString(s))

template raw*(n: JSName): JSStringRef = JSStringRef(n)

proc release*(n: JSName) =
  ## release a name made with `jsName`. It must not be used afterwards.
  JSStringRelease(n.raw)

proc `$`*(n: JSName): string = $n.raw

# ---------------------------------------------------------------- errors

proc toStringSafe*(v: JSValueRef, ctx: JSContextRef): string =
  ## best-effort String(v) that never raises: if the conversion throws,
  ## a description is returned instead. Use this where raising is not possible
  ## (e.g. in native callbacks or while formatting another error).
  if v == nil: return "null"
  var ex: JSValueRef
  let s = JSValueToStringCopy(ctx, v, ex.addr)
  if s == nil:
    if ex != nil:
      let s2 = JSValueToStringCopy(ctx, ex, nil)
      if s2 != nil:
        result = "<value could not be converted to a string: " & $s2 & ">"
        JSStringRelease(s2)
        return
    return "<value could not be converted to a string>"
  result = $s
  JSStringRelease(s)

proc errorMessage*(ctx: JSContextRef, exception: JSValueRef): string =
  ## format an exception value (never raises). Includes the stack if one is present.
  result = exception.toStringSafe(ctx)
  if JSValueIsObject(ctx, exception):
    let o = cast[JSObjectRef](exception)
    withJSString(stackName, "stack"):
      var ex: JSValueRef
      let st = JSObjectGetProperty(ctx, o, stackName, ex.addr)
      if ex == nil and st != nil and JSValueIsString(ctx, st):
        let s = st.toStringSafe(ctx)
        if s.len > 0:
          result.add "\n"
          result.add s

template check*(ctx: JSContextRef, exception: JSValueRef, msg: string = "") =
  if unlikely(exception != nil):
    var m = errorMessage(ctx, exception)
    if msg.len > 0: m = msg & ": " & m
    raise newException(JSError, m)

proc toString*(v: JSValueRef, ctx: JSContextRef): string =
  ## String(v) in javascript. Raises JSError if the conversion throws.
  if v == nil: return "null"
  var ex: JSValueRef
  let s = JSValueToStringCopy(ctx, v, ex.addr)
  ctx.check(ex)
  if s == nil: return ""
  result = $s
  JSStringRelease(s)

# ---------------------------------------------------------------- values

proc toJS*(ctx: JSContextRef, v: bool): JSValueRef {.inline.} = JSValueMakeBoolean(ctx, v)
proc toJS*(ctx: JSContextRef, v: SomeNumber): JSValueRef {.inline.} = JSValueMakeNumber(ctx, v.cdouble)
proc toJS*(ctx: JSContextRef, v: string): JSValueRef {.inline.} =
  let s = newJSString(v)
  result = JSValueMakeString(ctx, s)
  JSStringRelease(s)
proc toJS*(ctx: JSContextRef, v: cstring): JSValueRef {.inline.} =
  let s = JSStringCreateWithUTF8CString(v)
  result = JSValueMakeString(ctx, s)
  JSStringRelease(s)
proc toJS*(ctx: JSContextRef, v: JSValueRef): JSValueRef {.inline.} = v

proc undefined*(ctx: JSContextRef): JSValueRef {.inline.} = JSValueMakeUndefined(ctx)
proc null*(ctx: JSContextRef): JSValueRef {.inline.} = JSValueMakeNull(ctx)

proc newArray*(ctx: JSContextRef, values: openArray[JSValueRef]): JSObjectRef =
  ## make an array from values. If `values` lives in Nim heap memory (e.g. a
  ## seq) the values must be protected (see the module docs).
  var ex: JSValueRef
  if values.len == 0:
    result = JSObjectMakeArray(ctx, 0, nil, ex.addr)
  else:
    result = JSObjectMakeArray(ctx, values.len.csize_t, values[0].unsafeAddr, ex.addr)
  ctx.check(ex)

proc toJS*[T: SomeNumber|string|bool](ctx: JSContextRef, values: openArray[T]): JSValueRef =
  var vs = newSeq[JSValueRef](values.len)
  when T is string:
    # vs is in the Nim heap where the GC can't see it, so each string must be
    # protected until the array holds it.
    var n = 0
    try:
      for i, v in values:
        vs[i] = ctx.toJS(v)
        JSValueProtect(ctx, vs[i])
        n = i + 1
      result = ctx.newArray(vs)
    finally:
      for i in 0..<n: JSValueUnprotect(ctx, vs[i])
  else:
    # numbers and booleans are immediate values, not heap objects.
    for i, v in values: vs[i] = ctx.toJS(v)
    result = ctx.newArray(vs)

proc newObject*(ctx: JSContextRef): JSObjectRef {.inline.} = JSObjectMake(ctx, nil, nil)

proc toBool*(v: JSValueRef, ctx: JSContextRef): bool {.inline.} = JSValueToBoolean(ctx, v)
proc toFloat*(v: JSValueRef, ctx: JSContextRef): float {.inline.} =
  var ex: JSValueRef
  result = JSValueToNumber(ctx, v, ex.addr).float
  ctx.check(ex)

proc isUndefined*(v: JSValueRef, ctx: JSContextRef): bool {.inline.} = JSValueIsUndefined(ctx, v)
proc isObject*(v: JSValueRef, ctx: JSContextRef): bool {.inline.} = JSValueIsObject(ctx, v)
proc toObject*(v: JSValueRef, ctx: JSContextRef): JSObjectRef {.inline.} =
  var ex: JSValueRef
  result = JSValueToObject(ctx, v, ex.addr)
  ctx.check(ex)

proc protect*(ctx: JSContextRef, v: JSValueRef) {.inline.} = JSValueProtect(ctx, v)
proc unprotect*(ctx: JSContextRef, v: JSValueRef) {.inline.} = JSValueUnprotect(ctx, v)

proc toJSON*(ctx: JSContextRef, v: JSValueRef, indent = 0): string =
  var ex: JSValueRef
  let s = JSValueCreateJSONString(ctx, v, indent.cuint, ex.addr)
  ctx.check(ex)
  if s == nil: return "undefined"
  result = $s
  JSStringRelease(s)

# ---------------------------------------------------------------- properties

proc `[]=`*(ctx: JSContextRef, obj: JSObjectRef, name: JSName, value: JSValueRef) {.inline.} =
  var ex: JSValueRef
  JSObjectSetProperty(ctx, obj, name.raw, value, kJSPropertyAttributeNone, ex.addr)
  ctx.check(ex)

proc `[]`*(ctx: JSContextRef, obj: JSObjectRef, name: JSName): JSValueRef {.inline.} =
  var ex: JSValueRef
  result = JSObjectGetProperty(ctx, obj, name.raw, ex.addr)
  ctx.check(ex)

proc setProp*[T](ctx: JSContextRef, obj: JSObjectRef, name: string, value: T) =
  withJSString(n, name):
    var ex: JSValueRef
    JSObjectSetProperty(ctx, obj, n, ctx.toJS(value), kJSPropertyAttributeNone, ex.addr)
    ctx.check(ex, "setting " & name)

proc setProp*[T](ctx: JSContextRef, obj: JSObjectRef, name: JSName, value: T) {.inline.} =
  ctx[obj, name] = ctx.toJS(value)

proc getProp*(ctx: JSContextRef, obj: JSObjectRef, name: string): JSValueRef =
  withJSString(n, name):
    var ex: JSValueRef
    result = JSObjectGetProperty(ctx, obj, n, ex.addr)
    ctx.check(ex, "getting " & name)

proc hasProp*(ctx: JSContextRef, obj: JSObjectRef, name: string): bool =
  withJSString(n, name):
    result = JSObjectHasProperty(ctx, obj, n)

proc delProp*(ctx: JSContextRef, obj: JSObjectRef, name: string): bool {.discardable.} =
  withJSString(n, name):
    var ex: JSValueRef
    result = JSObjectDeleteProperty(ctx, obj, n, ex.addr)
    ctx.check(ex)

template checkIndex(index: int) =
  if unlikely(index < 0 or index.uint64 > uint32.high.uint64):
    raise newException(IndexDefect, "jsc: index " & $index & " is outside 0.." & $uint32.high)

proc `[]=`*(ctx: JSContextRef, obj: JSObjectRef, index: int, value: JSValueRef) {.inline.} =
  ## obj[index] = value. Raises IndexDefect for indexes outside 0..uint32.high.
  checkIndex(index)
  var ex: JSValueRef
  JSObjectSetPropertyAtIndex(ctx, obj, index.cuint, value, ex.addr)
  ctx.check(ex)

proc `[]`*(ctx: JSContextRef, obj: JSObjectRef, index: int): JSValueRef {.inline.} =
  ## obj[index]. Raises IndexDefect for indexes outside 0..uint32.high.
  checkIndex(index)
  var ex: JSValueRef
  result = JSObjectGetPropertyAtIndex(ctx, obj, index.cuint, ex.addr)
  ctx.check(ex)

proc setGlobal*[T](c: JSContext, name: string, value: T) =
  c.ctx.setProp(c.global, name, value)

proc setGlobal*(c: JSContext, name: JSName, value: JSValueRef) {.inline.} =
  c.ctx[c.global, name] = value

proc getGlobal*(c: JSContext, name: string): JSValueRef =
  c.ctx.getProp(c.global, name)

proc propertyNames*(ctx: JSContextRef, obj: JSObjectRef): seq[string] =
  let arr = JSObjectCopyPropertyNames(ctx, obj)
  let n = JSPropertyNameArrayGetCount(arr).int
  result = newSeq[string](n)
  for i in 0..<n:
    result[i] = $JSPropertyNameArrayGetNameAtIndex(arr, i.csize_t)
  JSPropertyNameArrayRelease(arr)

# ---------------------------------------------------------------- evaluation

proc eval*(ctx: JSContextRef, code: string, sourceURL = ""): JSValueRef =
  ## evaluate a script and return the completion value.
  var ex: JSValueRef
  let src = newJSString(code)
  let url = if sourceURL.len > 0: newJSString(sourceURL) else: nil
  result = JSEvaluateScript(ctx, src, nil, url, 1, ex.addr)
  JSStringRelease(src)
  if url != nil: JSStringRelease(url)
  ctx.check(ex)

proc checkSyntax*(ctx: JSContextRef, code: string): string =
  ## returns "" if code is syntactically valid, else the error message.
  var ex: JSValueRef
  withJSString(src, code):
    if not JSCheckScriptSyntax(ctx, src, nil, 1, ex.addr):
      result = errorMessage(ctx, ex)

proc compileFunction*(ctx: JSContextRef, body: string, params: openArray[string] = [], name = "anonymous"): JSObjectRef =
  ## compile `body` as the body of a function taking `params`.
  ## The function is protected from garbage collection.
  var ex: JSValueRef
  var pnames = newSeq[JSStringRef](params.len)
  for i, p in params: pnames[i] = newJSString(p)
  let b = newJSString(body)
  let n = newJSString(name)
  result = JSObjectMakeFunction(ctx, n, params.len.cuint,
                                (if params.len > 0: pnames[0].addr else: nil),
                                b, nil, 1, ex.addr)
  for p in pnames: JSStringRelease(p)
  JSStringRelease(b)
  JSStringRelease(n)
  ctx.check(ex)
  ctx.protect(result)

proc call*(ctx: JSContextRef, fn: JSObjectRef, args: openArray[JSValueRef] = [], this: JSObjectRef = nil): JSValueRef {.inline.} =
  ## call fn. If `args` lives in Nim heap memory the values must be protected.
  var ex: JSValueRef
  result = JSObjectCallAsFunction(ctx, fn, this, args.len.csize_t,
                                  (if args.len > 0: args[0].unsafeAddr else: nil), ex.addr)
  ctx.check(ex)
  if unlikely(result == nil):
    raise newException(JSError, "jsc: call failed; the object is not a function")

proc newFunction*(ctx: JSContextRef, name: string, cb: JSObjectCallAsFunctionCallback): JSObjectRef =
  ## make a JS function backed by a native callback. The callback must not
  ## raise Nim exceptions (they cannot unwind through JSC); to throw in
  ## javascript, set `exception[]` and return nil. Use `toStringSafe` there.
  withJSString(n, name):
    result = JSObjectMakeFunctionWithCallback(ctx, n, cb)

proc garbageCollect*(ctx: JSContextRef) = JSGarbageCollect(ctx)

# ---------------------------------------------------------------- typed arrays

proc newTypedArrayNoCopy*(ctx: JSContextRef, kind: JSTypedArrayType, data: pointer, byteLength: int): JSObjectRef =
  ## a typed array that views `data` directly (no copy). The memory must
  ## outlive every JS reference to the array; it is never freed by JSC.
  if byteLength < 0:
    raise newException(ValueError, "jsc: negative typed array byte length: " & $byteLength)
  if data == nil and byteLength > 0:
    raise newException(ValueError, "jsc: nil data for a typed array of " & $byteLength & " bytes")
  if kind in {kJSTypedArrayTypeNone, kJSTypedArrayTypeArrayBuffer}:
    raise newException(ValueError, "jsc: " & $kind & " is not a typed array type")
  var ex: JSValueRef
  result = JSObjectMakeTypedArrayWithBytesNoCopy(ctx, kind, data, byteLength.csize_t, nil, nil, ex.addr)
  ctx.check(ex)
  if result == nil:
    raise newException(JSError, "jsc: could not create a typed array of type " & $kind)

template typedArrayKind*(T: typedesc): JSTypedArrayType =
  when T is int8: kJSTypedArrayTypeInt8Array
  elif T is uint8: kJSTypedArrayTypeUint8Array
  elif T is int16: kJSTypedArrayTypeInt16Array
  elif T is uint16: kJSTypedArrayTypeUint16Array
  elif T is int32: kJSTypedArrayTypeInt32Array
  elif T is uint32: kJSTypedArrayTypeUint32Array
  elif T is float32: kJSTypedArrayTypeFloat32Array
  elif T is float64: kJSTypedArrayTypeFloat64Array
  else: {.error: "unsupported typed array element type".}

proc newTypedArray*[T](ctx: JSContextRef, data: ptr UncheckedArray[T], len: int): JSObjectRef {.inline.} =
  ## a typed array viewing `len` elements at `data` (no copy). See `newTypedArrayNoCopy`.
  if len < 0:
    raise newException(ValueError, "jsc: negative typed array length: " & $len)
  if len > high(int) div sizeof(T):
    raise newException(ValueError, "jsc: typed array length overflows: " & $len)
  ctx.newTypedArrayNoCopy(typedArrayKind(T), data, len * sizeof(T))

proc typedArrayData*(ctx: JSContextRef, arr: JSObjectRef): pointer =
  ## pointer to the first element of the typed array `arr` (honoring the view's
  ## byte offset, e.g. for `subarray`).
  ##
  ## JSC only guarantees the pointer until the next JSC API call (any proc in
  ## this module) or javascript execution; protecting `arr` does not extend that.
  ## Use it immediately, or own the memory instead: arrays made with
  ## `newTypedArray`/`newTypedArrayNoCopy` view Nim memory that you already hold.
  var ex: JSValueRef
  # the offset is fetched first so that no API call happens after the pointer is obtained.
  let offset = JSObjectGetTypedArrayByteOffset(ctx, arr, ex.addr)
  ctx.check(ex)
  let base = JSObjectGetTypedArrayBytesPtr(ctx, arr, ex.addr)
  if unlikely(ex != nil):
    ctx.check(ex)
  if base == nil: return nil
  result = cast[pointer](cast[uint](base) + offset.uint)

proc typedArrayLen*(ctx: JSContextRef, arr: JSObjectRef): int =
  ## number of elements in the typed array.
  var ex: JSValueRef
  result = JSObjectGetTypedArrayLength(ctx, arr, ex.addr).int
  ctx.check(ex)
