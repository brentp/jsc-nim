// Bun's WebKit fork does not take the JS API lock in the typed array functions
// of the C API (JSTypedArray.h); upstream WebKit does. Without the lock, a
// garbage collection triggered by one of them (e.g. when making a typed array)
// aborts in JSC::Heap::collect, because the thread's AtomStringTable is not the
// VM's. These wrappers take the lock; raw.nim binds them in place of the
// originals when the prebuilt library is used.
#include <JavaScriptCore/JavaScript.h>

namespace JSC {
class JSGlobalObject;
class JSLockHolder {  // JavaScriptCore/runtime/JSLock.h; exported by libJavaScriptCore
public:
    JSLockHolder(JSGlobalObject*);
    ~JSLockHolder();
private:
    void* m_vm;  // RefPtr<VM>
};
}

// a JSContextRef is the JSGlobalObject (JavaScriptCore/API/APICast.h).
#define LOCK(ctx) JSC::JSLockHolder lock(reinterpret_cast<JSC::JSGlobalObject*>(const_cast<OpaqueJSContext*>(ctx)))

extern "C" {

JSTypedArrayType jscnim_JSValueGetTypedArrayType(JSContextRef ctx, JSValueRef v, JSValueRef* e) { LOCK(ctx); return JSValueGetTypedArrayType(ctx, v, e); }
JSObjectRef jscnim_JSObjectMakeTypedArray(JSContextRef ctx, JSTypedArrayType t, size_t n, JSValueRef* e) { LOCK(ctx); return JSObjectMakeTypedArray(ctx, t, n, e); }
JSObjectRef jscnim_JSObjectMakeTypedArrayWithBytesNoCopy(JSContextRef ctx, JSTypedArrayType t, void* b, size_t n, JSTypedArrayBytesDeallocator d, void* dc, JSValueRef* e) { LOCK(ctx); return JSObjectMakeTypedArrayWithBytesNoCopy(ctx, t, b, n, d, dc, e); }
JSObjectRef jscnim_JSObjectMakeTypedArrayWithArrayBuffer(JSContextRef ctx, JSTypedArrayType t, JSObjectRef b, JSValueRef* e) { LOCK(ctx); return JSObjectMakeTypedArrayWithArrayBuffer(ctx, t, b, e); }
JSObjectRef jscnim_JSObjectMakeTypedArrayWithArrayBufferAndOffset(JSContextRef ctx, JSTypedArrayType t, JSObjectRef b, size_t o, size_t n, JSValueRef* e) { LOCK(ctx); return JSObjectMakeTypedArrayWithArrayBufferAndOffset(ctx, t, b, o, n, e); }
void* jscnim_JSObjectGetTypedArrayBytesPtr(JSContextRef ctx, JSObjectRef o, JSValueRef* e) { LOCK(ctx); return JSObjectGetTypedArrayBytesPtr(ctx, o, e); }
size_t jscnim_JSObjectGetTypedArrayLength(JSContextRef ctx, JSObjectRef o, JSValueRef* e) { LOCK(ctx); return JSObjectGetTypedArrayLength(ctx, o, e); }
size_t jscnim_JSObjectGetTypedArrayByteLength(JSContextRef ctx, JSObjectRef o, JSValueRef* e) { LOCK(ctx); return JSObjectGetTypedArrayByteLength(ctx, o, e); }
size_t jscnim_JSObjectGetTypedArrayByteOffset(JSContextRef ctx, JSObjectRef o, JSValueRef* e) { LOCK(ctx); return JSObjectGetTypedArrayByteOffset(ctx, o, e); }
JSObjectRef jscnim_JSObjectGetTypedArrayBuffer(JSContextRef ctx, JSObjectRef o, JSValueRef* e) { LOCK(ctx); return JSObjectGetTypedArrayBuffer(ctx, o, e); }
JSObjectRef jscnim_JSObjectMakeArrayBufferWithBytesNoCopy(JSContextRef ctx, void* b, size_t n, JSTypedArrayBytesDeallocator d, void* dc, JSValueRef* e) { LOCK(ctx); return JSObjectMakeArrayBufferWithBytesNoCopy(ctx, b, n, d, dc, e); }
void* jscnim_JSObjectGetArrayBufferBytesPtr(JSContextRef ctx, JSObjectRef o, JSValueRef* e) { LOCK(ctx); return JSObjectGetArrayBufferBytesPtr(ctx, o, e); }
size_t jscnim_JSObjectGetArrayBufferByteLength(JSContextRef ctx, JSObjectRef o, JSValueRef* e) { LOCK(ctx); return JSObjectGetArrayBufferByteLength(ctx, o, e); }

}
