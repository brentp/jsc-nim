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
## Values returned to Nim (`JSValueRef`/`JSObjectRef`) are only guaranteed to
## stay alive while they are reachable from JavaScript or on the C stack. Use
## `protect` for values you keep in Nim heap memory across calls into JS.

import ./jsc/raw
export raw

type
  JSError* = object of CatchableError
    ## raised when evaluating JavaScript throws.

  JSContext* = ref object
    ctx*: JSGlobalContextRef
    global*: JSObjectRef

  JSName* = distinct JSStringRef
    ## an interned, retained property name. Create these once and reuse them;
    ## they are never released.

var defaultGroup: JSContextGroupRef

proc newJSContext*(): JSContext =
  ## create a new global context. All contexts share a single VM (context group).
  if defaultGroup == nil:
    defaultGroup = JSContextGroupCreate()
  result = JSContext(ctx: JSGlobalContextCreateInGroup(defaultGroup, nil))
  result.global = JSContextGetGlobalObject(result.ctx)

converter toContextRef*(c: JSContext): JSContextRef {.inline.} = c.ctx

# ---------------------------------------------------------------- strings

proc `$`*(s: JSStringRef): string =
  ## copy a JSStringRef to a Nim string (UTF-8)
  if s == nil: return ""
  let n = JSStringGetMaximumUTF8CStringSize(s)
  result = newString(n.int)
  let written = JSStringGetUTF8CString(s, result.cstring, n)
  result.setLen(max(0, written.int - 1))

template withJSString*(name: untyped, s: string, body: untyped) =
  ## create a temporary JSStringRef `name` from `s` for the duration of body.
  let name = JSStringCreateWithUTF8CString(s.cstring)
  try:
    body
  finally:
    JSStringRelease(name)

proc jsName*(s: string): JSName =
  ## create a reusable property name.
  JSName(JSStringCreateWithUTF8CString(s.cstring))

template raw*(n: JSName): JSStringRef = JSStringRef(n)

proc `$`*(n: JSName): string = $n.raw

# ---------------------------------------------------------------- errors

proc toString*(v: JSValueRef, ctx: JSContextRef): string =
  ## String(v) in javascript.
  if v == nil: return "null"
  var ex: JSValueRef
  let s = JSValueToStringCopy(ctx, v, ex.addr)
  if s == nil: return "<unprintable value>"
  result = $s
  JSStringRelease(s)

proc errorMessage*(ctx: JSContextRef, exception: JSValueRef): string =
  ## format an exception value. Includes the stack if one is present.
  result = exception.toString(ctx)
  if JSValueIsObject(ctx, exception):
    let o = cast[JSObjectRef](exception)
    withJSString(stackName, "stack"):
      let st = JSObjectGetProperty(ctx, o, stackName, nil)
      if st != nil and JSValueIsString(ctx, st):
        let s = st.toString(ctx)
        if s.len > 0:
          result.add "\n"
          result.add s

template check*(ctx: JSContextRef, exception: JSValueRef, msg: string = "") =
  if unlikely(exception != nil):
    var m = errorMessage(ctx, exception)
    if msg.len > 0: m = msg & ": " & m
    raise newException(JSError, m)

# ---------------------------------------------------------------- values

proc toJS*(ctx: JSContextRef, v: bool): JSValueRef {.inline.} = JSValueMakeBoolean(ctx, v)
proc toJS*(ctx: JSContextRef, v: SomeNumber): JSValueRef {.inline.} = JSValueMakeNumber(ctx, v.cdouble)
proc toJS*(ctx: JSContextRef, v: string): JSValueRef {.inline.} =
  let s = JSStringCreateWithUTF8CString(v.cstring)
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
  var ex: JSValueRef
  if values.len == 0:
    result = JSObjectMakeArray(ctx, 0, nil, ex.addr)
  else:
    result = JSObjectMakeArray(ctx, values.len.csize_t, values[0].unsafeAddr, ex.addr)
  ctx.check(ex)

proc toJS*[T: SomeNumber|string|bool](ctx: JSContextRef, values: openArray[T]): JSValueRef =
  var vs = newSeq[JSValueRef](values.len)
  for i, v in values: vs[i] = ctx.toJS(v)
  ctx.newArray(vs)

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

proc `[]=`*(ctx: JSContextRef, obj: JSObjectRef, index: int, value: JSValueRef) {.inline.} =
  var ex: JSValueRef
  JSObjectSetPropertyAtIndex(ctx, obj, index.cuint, value, ex.addr)
  ctx.check(ex)

proc `[]`*(ctx: JSContextRef, obj: JSObjectRef, index: int): JSValueRef {.inline.} =
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
  let src = JSStringCreateWithUTF8CString(code.cstring)
  let url = if sourceURL.len > 0: JSStringCreateWithUTF8CString(sourceURL.cstring) else: nil
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
  for i, p in params: pnames[i] = JSStringCreateWithUTF8CString(p.cstring)
  let b = JSStringCreateWithUTF8CString(body.cstring)
  let n = JSStringCreateWithUTF8CString(name.cstring)
  result = JSObjectMakeFunction(ctx, n, params.len.cuint,
                                (if params.len > 0: pnames[0].addr else: nil),
                                b, nil, 1, ex.addr)
  for p in pnames: JSStringRelease(p)
  JSStringRelease(b)
  JSStringRelease(n)
  ctx.check(ex)
  ctx.protect(result)

proc call*(ctx: JSContextRef, fn: JSObjectRef, args: openArray[JSValueRef] = [], this: JSObjectRef = nil): JSValueRef {.inline.} =
  var ex: JSValueRef
  result = JSObjectCallAsFunction(ctx, fn, this, args.len.csize_t,
                                  (if args.len > 0: args[0].unsafeAddr else: nil), ex.addr)
  ctx.check(ex)

proc newFunction*(ctx: JSContextRef, name: string, cb: JSObjectCallAsFunctionCallback): JSObjectRef =
  ## make a JS function backed by a native callback.
  withJSString(n, name):
    result = JSObjectMakeFunctionWithCallback(ctx, n, cb)

proc garbageCollect*(ctx: JSContextRef) = JSGarbageCollect(ctx)

# ---------------------------------------------------------------- typed arrays

proc newTypedArrayNoCopy*(ctx: JSContextRef, kind: JSTypedArrayType, data: pointer, byteLength: int): JSObjectRef =
  ## a typed array that views `data` directly (no copy). The memory must
  ## outlive every JS reference to the array; it is never freed by JSC.
  var ex: JSValueRef
  result = JSObjectMakeTypedArrayWithBytesNoCopy(ctx, kind, data, byteLength.csize_t, nil, nil, ex.addr)
  ctx.check(ex)

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
  ctx.newTypedArrayNoCopy(typedArrayKind(T), data, len * sizeof(T))

proc typedArrayData*(ctx: JSContextRef, arr: JSObjectRef): pointer {.inline.} =
  var ex: JSValueRef
  result = JSObjectGetTypedArrayBytesPtr(ctx, arr, ex.addr)
  ctx.check(ex)
