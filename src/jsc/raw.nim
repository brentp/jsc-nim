## Raw bindings to the JavaScriptCore C API (JavaScriptCore/JavaScript.h).
##
## Only the stable public C API is bound here. Linking is configured in
## `jsc/link.nim`, which is imported for its side effects.

import ./link
export link

type
  OpaqueJSContextGroup = object
  OpaqueJSContext = object
  OpaqueJSString = object
  OpaqueJSClass = object
  OpaqueJSPropertyNameArray = object
  OpaqueJSPropertyNameAccumulator = object
  OpaqueJSValue = object

  JSContextGroupRef* = ptr OpaqueJSContextGroup
  JSContextRef* = ptr OpaqueJSContext
  JSGlobalContextRef* = ptr OpaqueJSContext
  JSStringRef* = ptr OpaqueJSString
  JSClassRef* = ptr OpaqueJSClass
  JSPropertyNameArrayRef* = ptr OpaqueJSPropertyNameArray
  JSPropertyNameAccumulatorRef* = ptr OpaqueJSPropertyNameAccumulator
  JSValueRef* = ptr OpaqueJSValue
  JSObjectRef* = ptr OpaqueJSValue

  JSChar* = uint16

  JSType* {.size: sizeof(cint).} = enum
    kJSTypeUndefined, kJSTypeNull, kJSTypeBoolean, kJSTypeNumber,
    kJSTypeString, kJSTypeObject, kJSTypeSymbol, kJSTypeBigInt

  JSTypedArrayType* {.size: sizeof(cint).} = enum
    kJSTypedArrayTypeInt8Array, kJSTypedArrayTypeInt16Array,
    kJSTypedArrayTypeInt32Array, kJSTypedArrayTypeUint8Array,
    kJSTypedArrayTypeUint8ClampedArray, kJSTypedArrayTypeUint16Array,
    kJSTypedArrayTypeUint32Array, kJSTypedArrayTypeFloat32Array,
    kJSTypedArrayTypeFloat64Array, kJSTypedArrayTypeArrayBuffer,
    kJSTypedArrayTypeNone, kJSTypedArrayTypeBigInt64Array,
    kJSTypedArrayTypeBigUint64Array

  JSPropertyAttributes* = cuint
  JSClassAttributes* = cuint

  JSObjectInitializeCallback* = proc (ctx: JSContextRef, obj: JSObjectRef) {.cdecl.}
  JSObjectFinalizeCallback* = proc (obj: JSObjectRef) {.cdecl.}
  JSObjectHasPropertyCallback* = proc (ctx: JSContextRef, obj: JSObjectRef, name: JSStringRef): bool {.cdecl.}
  JSObjectGetPropertyCallback* = proc (ctx: JSContextRef, obj: JSObjectRef, name: JSStringRef, exception: ptr JSValueRef): JSValueRef {.cdecl.}
  JSObjectSetPropertyCallback* = proc (ctx: JSContextRef, obj: JSObjectRef, name: JSStringRef, value: JSValueRef, exception: ptr JSValueRef): bool {.cdecl.}
  JSObjectDeletePropertyCallback* = proc (ctx: JSContextRef, obj: JSObjectRef, name: JSStringRef, exception: ptr JSValueRef): bool {.cdecl.}
  JSObjectGetPropertyNamesCallback* = proc (ctx: JSContextRef, obj: JSObjectRef, names: JSPropertyNameAccumulatorRef) {.cdecl.}
  JSObjectCallAsFunctionCallback* = proc (ctx: JSContextRef, function: JSObjectRef, thisObject: JSObjectRef, argumentCount: csize_t, arguments: ptr UncheckedArray[JSValueRef], exception: ptr JSValueRef): JSValueRef {.cdecl.}
  JSObjectCallAsConstructorCallback* = proc (ctx: JSContextRef, constructor: JSObjectRef, argumentCount: csize_t, arguments: ptr UncheckedArray[JSValueRef], exception: ptr JSValueRef): JSObjectRef {.cdecl.}
  JSObjectHasInstanceCallback* = proc (ctx: JSContextRef, constructor: JSObjectRef, possibleInstance: JSValueRef, exception: ptr JSValueRef): bool {.cdecl.}
  JSObjectConvertToTypeCallback* = proc (ctx: JSContextRef, obj: JSObjectRef, typ: JSType, exception: ptr JSValueRef): JSValueRef {.cdecl.}
  JSTypedArrayBytesDeallocator* = proc (bytes: pointer, deallocatorContext: pointer) {.cdecl.}

  JSStaticValue* = object
    name*: cstring
    getProperty*: JSObjectGetPropertyCallback
    setProperty*: JSObjectSetPropertyCallback
    attributes*: JSPropertyAttributes

  JSStaticFunction* = object
    name*: cstring
    callAsFunction*: JSObjectCallAsFunctionCallback
    attributes*: JSPropertyAttributes

  JSClassDefinition* = object
    version*: cint
    attributes*: JSClassAttributes
    className*: cstring
    parentClass*: JSClassRef
    staticValues*: ptr JSStaticValue
    staticFunctions*: ptr JSStaticFunction
    initialize*: JSObjectInitializeCallback
    finalize*: JSObjectFinalizeCallback
    hasProperty*: JSObjectHasPropertyCallback
    getProperty*: JSObjectGetPropertyCallback
    setProperty*: JSObjectSetPropertyCallback
    deleteProperty*: JSObjectDeletePropertyCallback
    getPropertyNames*: JSObjectGetPropertyNamesCallback
    callAsFunction*: JSObjectCallAsFunctionCallback
    callAsConstructor*: JSObjectCallAsConstructorCallback
    hasInstance*: JSObjectHasInstanceCallback
    convertToType*: JSObjectConvertToTypeCallback

const
  kJSPropertyAttributeNone* = 0.JSPropertyAttributes
  kJSPropertyAttributeReadOnly* = (1 shl 1).JSPropertyAttributes
  kJSPropertyAttributeDontEnum* = (1 shl 2).JSPropertyAttributes
  kJSPropertyAttributeDontDelete* = (1 shl 3).JSPropertyAttributes
  kJSClassAttributeNone* = 0.JSClassAttributes
  kJSClassAttributeNoAutomaticPrototype* = (1 shl 1).JSClassAttributes

# the typed array functions. With the prebuilt (Bun) library these bind to
# wrappers that take the API lock, which the Bun fork omits (see bunlock.c).
when jscBackend == "bun-prebuilt":
  {.pragma: typedArrayApi, cdecl, importc: "jscnim_$1".}
else:
  {.pragma: typedArrayApi, cdecl, importc.}

{.push cdecl, importc.}

# JSBase.h
proc JSEvaluateScript*(ctx: JSContextRef, script: JSStringRef, thisObject: JSObjectRef, sourceURL: JSStringRef, startingLineNumber: cint, exception: ptr JSValueRef): JSValueRef
proc JSCheckScriptSyntax*(ctx: JSContextRef, script: JSStringRef, sourceURL: JSStringRef, startingLineNumber: cint, exception: ptr JSValueRef): bool
proc JSGarbageCollect*(ctx: JSContextRef)

# JSContextRef.h
proc JSContextGroupCreate*(): JSContextGroupRef
proc JSContextGroupRetain*(group: JSContextGroupRef): JSContextGroupRef
proc JSContextGroupRelease*(group: JSContextGroupRef)
proc JSGlobalContextCreate*(globalObjectClass: JSClassRef): JSGlobalContextRef
proc JSGlobalContextCreateInGroup*(group: JSContextGroupRef, globalObjectClass: JSClassRef): JSGlobalContextRef
proc JSGlobalContextRetain*(ctx: JSGlobalContextRef): JSGlobalContextRef
proc JSGlobalContextRelease*(ctx: JSGlobalContextRef)
proc JSContextGetGlobalObject*(ctx: JSContextRef): JSObjectRef
proc JSContextGetGroup*(ctx: JSContextRef): JSContextGroupRef
proc JSContextGetGlobalContext*(ctx: JSContextRef): JSGlobalContextRef

# JSStringRef.h
proc JSStringCreateWithCharacters*(chars: ptr JSChar, numChars: csize_t): JSStringRef
proc JSStringCreateWithUTF8CString*(s: cstring): JSStringRef
proc JSStringRetain*(s: JSStringRef): JSStringRef
proc JSStringRelease*(s: JSStringRef)
proc JSStringGetLength*(s: JSStringRef): csize_t
proc JSStringGetCharactersPtr*(s: JSStringRef): ptr UncheckedArray[JSChar]
proc JSStringGetMaximumUTF8CStringSize*(s: JSStringRef): csize_t
proc JSStringGetUTF8CString*(s: JSStringRef, buffer: cstring, bufferSize: csize_t): csize_t
proc JSStringIsEqual*(a, b: JSStringRef): bool
proc JSStringIsEqualToUTF8CString*(a: JSStringRef, b: cstring): bool

# JSValueRef.h
proc JSValueGetType*(ctx: JSContextRef, value: JSValueRef): JSType
proc JSValueIsUndefined*(ctx: JSContextRef, value: JSValueRef): bool
proc JSValueIsNull*(ctx: JSContextRef, value: JSValueRef): bool
proc JSValueIsBoolean*(ctx: JSContextRef, value: JSValueRef): bool
proc JSValueIsNumber*(ctx: JSContextRef, value: JSValueRef): bool
proc JSValueIsString*(ctx: JSContextRef, value: JSValueRef): bool
proc JSValueIsObject*(ctx: JSContextRef, value: JSValueRef): bool
proc JSValueIsObjectOfClass*(ctx: JSContextRef, value: JSValueRef, jsClass: JSClassRef): bool
proc JSValueIsArray*(ctx: JSContextRef, value: JSValueRef): bool
proc JSValueIsEqual*(ctx: JSContextRef, a, b: JSValueRef, exception: ptr JSValueRef): bool
proc JSValueIsStrictEqual*(ctx: JSContextRef, a, b: JSValueRef): bool
proc JSValueMakeUndefined*(ctx: JSContextRef): JSValueRef
proc JSValueMakeNull*(ctx: JSContextRef): JSValueRef
proc JSValueMakeBoolean*(ctx: JSContextRef, b: bool): JSValueRef
proc JSValueMakeNumber*(ctx: JSContextRef, n: cdouble): JSValueRef
proc JSValueMakeString*(ctx: JSContextRef, s: JSStringRef): JSValueRef
proc JSValueMakeFromJSONString*(ctx: JSContextRef, s: JSStringRef): JSValueRef
proc JSValueCreateJSONString*(ctx: JSContextRef, value: JSValueRef, indent: cuint, exception: ptr JSValueRef): JSStringRef
proc JSValueToBoolean*(ctx: JSContextRef, value: JSValueRef): bool
proc JSValueToNumber*(ctx: JSContextRef, value: JSValueRef, exception: ptr JSValueRef): cdouble
proc JSValueToStringCopy*(ctx: JSContextRef, value: JSValueRef, exception: ptr JSValueRef): JSStringRef
proc JSValueToObject*(ctx: JSContextRef, value: JSValueRef, exception: ptr JSValueRef): JSObjectRef
proc JSValueProtect*(ctx: JSContextRef, value: JSValueRef)
proc JSValueUnprotect*(ctx: JSContextRef, value: JSValueRef)

# JSObjectRef.h
proc JSClassCreate*(definition: ptr JSClassDefinition): JSClassRef
proc JSClassRetain*(jsClass: JSClassRef): JSClassRef
proc JSClassRelease*(jsClass: JSClassRef)
proc JSObjectMake*(ctx: JSContextRef, jsClass: JSClassRef, data: pointer): JSObjectRef
proc JSObjectMakeFunctionWithCallback*(ctx: JSContextRef, name: JSStringRef, callAsFunction: JSObjectCallAsFunctionCallback): JSObjectRef
proc JSObjectMakeConstructor*(ctx: JSContextRef, jsClass: JSClassRef, callAsConstructor: JSObjectCallAsConstructorCallback): JSObjectRef
proc JSObjectMakeArray*(ctx: JSContextRef, argumentCount: csize_t, arguments: ptr JSValueRef, exception: ptr JSValueRef): JSObjectRef
proc JSObjectMakeError*(ctx: JSContextRef, argumentCount: csize_t, arguments: ptr JSValueRef, exception: ptr JSValueRef): JSObjectRef
proc JSObjectMakeRegExp*(ctx: JSContextRef, argumentCount: csize_t, arguments: ptr JSValueRef, exception: ptr JSValueRef): JSObjectRef
proc JSObjectMakeFunction*(ctx: JSContextRef, name: JSStringRef, parameterCount: cuint, parameterNames: ptr JSStringRef, body: JSStringRef, sourceURL: JSStringRef, startingLineNumber: cint, exception: ptr JSValueRef): JSObjectRef
proc JSObjectGetPrototype*(ctx: JSContextRef, obj: JSObjectRef): JSValueRef
proc JSObjectSetPrototype*(ctx: JSContextRef, obj: JSObjectRef, value: JSValueRef)
proc JSObjectHasProperty*(ctx: JSContextRef, obj: JSObjectRef, name: JSStringRef): bool
proc JSObjectGetProperty*(ctx: JSContextRef, obj: JSObjectRef, name: JSStringRef, exception: ptr JSValueRef): JSValueRef
proc JSObjectSetProperty*(ctx: JSContextRef, obj: JSObjectRef, name: JSStringRef, value: JSValueRef, attributes: JSPropertyAttributes, exception: ptr JSValueRef)
proc JSObjectDeleteProperty*(ctx: JSContextRef, obj: JSObjectRef, name: JSStringRef, exception: ptr JSValueRef): bool
proc JSObjectGetPropertyAtIndex*(ctx: JSContextRef, obj: JSObjectRef, index: cuint, exception: ptr JSValueRef): JSValueRef
proc JSObjectSetPropertyAtIndex*(ctx: JSContextRef, obj: JSObjectRef, index: cuint, value: JSValueRef, exception: ptr JSValueRef)
proc JSObjectGetPrivate*(obj: JSObjectRef): pointer
proc JSObjectSetPrivate*(obj: JSObjectRef, data: pointer): bool
proc JSObjectIsFunction*(ctx: JSContextRef, obj: JSObjectRef): bool
proc JSObjectCallAsFunction*(ctx: JSContextRef, obj: JSObjectRef, thisObject: JSObjectRef, argumentCount: csize_t, arguments: ptr JSValueRef, exception: ptr JSValueRef): JSValueRef
proc JSObjectIsConstructor*(ctx: JSContextRef, obj: JSObjectRef): bool
proc JSObjectCallAsConstructor*(ctx: JSContextRef, obj: JSObjectRef, argumentCount: csize_t, arguments: ptr JSValueRef, exception: ptr JSValueRef): JSObjectRef
proc JSObjectCopyPropertyNames*(ctx: JSContextRef, obj: JSObjectRef): JSPropertyNameArrayRef
proc JSPropertyNameArrayRetain*(arr: JSPropertyNameArrayRef): JSPropertyNameArrayRef
proc JSPropertyNameArrayRelease*(arr: JSPropertyNameArrayRef)
proc JSPropertyNameArrayGetCount*(arr: JSPropertyNameArrayRef): csize_t
proc JSPropertyNameArrayGetNameAtIndex*(arr: JSPropertyNameArrayRef, index: csize_t): JSStringRef
proc JSPropertyNameAccumulatorAddName*(acc: JSPropertyNameAccumulatorRef, name: JSStringRef)

{.pop.}

# JSTypedArray.h (not in the push above: typedArrayApi sets importc)
proc JSValueGetTypedArrayType*(ctx: JSContextRef, value: JSValueRef, exception: ptr JSValueRef): JSTypedArrayType {.typedArrayApi.}
proc JSObjectMakeTypedArray*(ctx: JSContextRef, arrayType: JSTypedArrayType, length: csize_t, exception: ptr JSValueRef): JSObjectRef {.typedArrayApi.}
proc JSObjectMakeTypedArrayWithBytesNoCopy*(ctx: JSContextRef, arrayType: JSTypedArrayType, bytes: pointer, byteLength: csize_t, bytesDeallocator: JSTypedArrayBytesDeallocator, deallocatorContext: pointer, exception: ptr JSValueRef): JSObjectRef {.typedArrayApi.}
proc JSObjectMakeTypedArrayWithArrayBuffer*(ctx: JSContextRef, arrayType: JSTypedArrayType, buffer: JSObjectRef, exception: ptr JSValueRef): JSObjectRef {.typedArrayApi.}
proc JSObjectMakeTypedArrayWithArrayBufferAndOffset*(ctx: JSContextRef, arrayType: JSTypedArrayType, buffer: JSObjectRef, byteOffset: csize_t, length: csize_t, exception: ptr JSValueRef): JSObjectRef {.typedArrayApi.}
proc JSObjectGetTypedArrayBytesPtr*(ctx: JSContextRef, obj: JSObjectRef, exception: ptr JSValueRef): pointer {.typedArrayApi.}
proc JSObjectGetTypedArrayLength*(ctx: JSContextRef, obj: JSObjectRef, exception: ptr JSValueRef): csize_t {.typedArrayApi.}
proc JSObjectGetTypedArrayByteLength*(ctx: JSContextRef, obj: JSObjectRef, exception: ptr JSValueRef): csize_t {.typedArrayApi.}
proc JSObjectGetTypedArrayByteOffset*(ctx: JSContextRef, obj: JSObjectRef, exception: ptr JSValueRef): csize_t {.typedArrayApi.}
proc JSObjectGetTypedArrayBuffer*(ctx: JSContextRef, obj: JSObjectRef, exception: ptr JSValueRef): JSObjectRef {.typedArrayApi.}
proc JSObjectMakeArrayBufferWithBytesNoCopy*(ctx: JSContextRef, bytes: pointer, byteLength: csize_t, bytesDeallocator: JSTypedArrayBytesDeallocator, deallocatorContext: pointer, exception: ptr JSValueRef): JSObjectRef {.typedArrayApi.}
proc JSObjectGetArrayBufferBytesPtr*(ctx: JSContextRef, obj: JSObjectRef, exception: ptr JSValueRef): pointer {.typedArrayApi.}
proc JSObjectGetArrayBufferByteLength*(ctx: JSContextRef, obj: JSObjectRef, exception: ptr JSValueRef): csize_t {.typedArrayApi.}


