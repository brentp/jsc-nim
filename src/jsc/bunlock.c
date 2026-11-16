// Bun's WebKit fork does not take the JS API lock in the typed array functions
// of the C API (JSTypedArray.h); upstream WebKit does. Without the lock, a
// garbage collection triggered by one of them (e.g. when making a typed array)
// aborts in JSC::Heap::collect, because the thread's AtomStringTable is not the
// VM's. These wrappers take the lock; raw.nim binds them in place of the
// originals when the prebuilt library is used.
//
// The lock is JSC::JSLockHolder (JavaScriptCore/runtime/JSLock.h), a C++ class
// holding one pointer (RefPtr<VM>). Its constructor and destructor are exported
// by libJavaScriptCore; they are called here by their mangled names so that no
// C++ compiler is needed. A JSContextRef is the JSGlobalObject* the constructor
// takes (JavaScriptCore/API/APICast.h).
#include <JavaScriptCore/JavaScript.h>

typedef struct { void* vm; } LockHolder;
extern void _ZN3JSC12JSLockHolderC1EPNS_14JSGlobalObjectE(LockHolder* self, JSContextRef globalObject);
extern void _ZN3JSC12JSLockHolderD1Ev(LockHolder* self);

#define WRAP(ret, name, params, args) \
  ret jscnim_##name params { \
    LockHolder lock; \
    _ZN3JSC12JSLockHolderC1EPNS_14JSGlobalObjectE(&lock, ctx); \
    ret r = name args; \
    _ZN3JSC12JSLockHolderD1Ev(&lock); \
    return r; \
  }

WRAP(JSTypedArrayType, JSValueGetTypedArrayType, (JSContextRef ctx, JSValueRef v, JSValueRef* e), (ctx, v, e))
WRAP(JSObjectRef, JSObjectMakeTypedArray, (JSContextRef ctx, JSTypedArrayType t, size_t n, JSValueRef* e), (ctx, t, n, e))
WRAP(JSObjectRef, JSObjectMakeTypedArrayWithBytesNoCopy, (JSContextRef ctx, JSTypedArrayType t, void* b, size_t n, JSTypedArrayBytesDeallocator d, void* dc, JSValueRef* e), (ctx, t, b, n, d, dc, e))
WRAP(JSObjectRef, JSObjectMakeTypedArrayWithArrayBuffer, (JSContextRef ctx, JSTypedArrayType t, JSObjectRef b, JSValueRef* e), (ctx, t, b, e))
WRAP(JSObjectRef, JSObjectMakeTypedArrayWithArrayBufferAndOffset, (JSContextRef ctx, JSTypedArrayType t, JSObjectRef b, size_t o, size_t n, JSValueRef* e), (ctx, t, b, o, n, e))
WRAP(void*, JSObjectGetTypedArrayBytesPtr, (JSContextRef ctx, JSObjectRef o, JSValueRef* e), (ctx, o, e))
WRAP(size_t, JSObjectGetTypedArrayLength, (JSContextRef ctx, JSObjectRef o, JSValueRef* e), (ctx, o, e))
WRAP(size_t, JSObjectGetTypedArrayByteLength, (JSContextRef ctx, JSObjectRef o, JSValueRef* e), (ctx, o, e))
WRAP(size_t, JSObjectGetTypedArrayByteOffset, (JSContextRef ctx, JSObjectRef o, JSValueRef* e), (ctx, o, e))
WRAP(JSObjectRef, JSObjectGetTypedArrayBuffer, (JSContextRef ctx, JSObjectRef o, JSValueRef* e), (ctx, o, e))
WRAP(JSObjectRef, JSObjectMakeArrayBufferWithBytesNoCopy, (JSContextRef ctx, void* b, size_t n, JSTypedArrayBytesDeallocator d, void* dc, JSValueRef* e), (ctx, b, n, d, dc, e))
WRAP(void*, JSObjectGetArrayBufferBytesPtr, (JSContextRef ctx, JSObjectRef o, JSValueRef* e), (ctx, o, e))
WRAP(size_t, JSObjectGetArrayBufferByteLength, (JSContextRef ctx, JSObjectRef o, JSValueRef* e), (ctx, o, e))
