#!/usr/bin/env bash
# Download a prebuilt, statically-linkable JavaScriptCore (from Bun's WebKit
# fork, https://github.com/oven-sh/WebKit) plus the matching mimalloc sources.
#
# usage: fetch-jsc.sh <dest-dir> <webkit-version> <mimalloc-commit> <arch: amd64|arm64> [libc: glibc|musl]
#
# Environment overrides (for offline / air-gapped builds):
#   JSC_WEBKIT_TARBALL   path to an already-downloaded bun-webkit-linux-*.tar.gz
#   JSC_MIMALLOC_TARBALL path to an already-downloaded mimalloc source tarball
#
# The result is laid out as:
#   <dest>/lib/*.a              JavaScriptCore, WTF, bmalloc, ICU (debug info stripped)
#   <dest>/include/JavaScriptCore/*.h   public C API headers
#   <dest>/mimalloc/{src,include}
#   <dest>/VERSION
set -euo pipefail

dest=$1
webkit_version=$2
mimalloc_commit=$3
arch=$4
libc=${5:-glibc}

suffix=""
if [[ "$libc" == "musl" ]]; then suffix="-musl"; fi
webkit_url="https://github.com/oven-sh/WebKit/releases/download/autobuild-${webkit_version}/bun-webkit-linux-${arch}${suffix}.tar.gz"
mimalloc_url="https://github.com/oven-sh/mimalloc/archive/${mimalloc_commit}.tar.gz"

download() { # url out
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    echo "[jsc-nim] need curl or wget to download $1" >&2
    return 1
  fi
}

# never replace a directory that jsc-nim did not create: it must be missing,
# empty, or carry the marker written below (or the VERSION file of older caches).
is_ours() {
  [[ ! -e "$1" ]] && return 0
  [[ -d "$1" ]] || return 1
  [[ -z "$(ls -A "$1")" ]] && return 0
  [[ -f "$1/.jsc-nim-cache" ]] && return 0
  [[ -f "$1/VERSION" && -f "$1/lib/libJavaScriptCore.a" ]] && head -1 "$1/VERSION" | grep -q '^webkit=' && return 0
  return 1
}
if ! is_ours "$dest"; then
  echo "[jsc-nim] refusing to replace $dest: it exists and was not created by jsc-nim" >&2
  exit 1
fi

mkdir -p "$(dirname "$dest")"
work=$(mktemp -d "${dest}.tmp.XXXXXX")
trap 'rm -rf "$work"' EXIT

echo "[jsc-nim] fetching JavaScriptCore ${webkit_version} (${arch}${suffix}) into ${dest}" >&2
if [[ -n "${JSC_WEBKIT_TARBALL:-}" ]]; then
  cp "$JSC_WEBKIT_TARBALL" "$work/webkit.tar.gz"
else
  download "$webkit_url" "$work/webkit.tar.gz"
fi

mkdir -p "$work/x" "$work/out/lib" "$work/out/include/JavaScriptCore"
tar -xzf "$work/webkit.tar.gz" -C "$work/x" --wildcards '*/lib/*.a' '*/include/JavaScriptCore/*'
rm -f "$work/webkit.tar.gz"
root=$(find "$work/x" -mindepth 1 -maxdepth 1 -type d | head -1)
mv "$root"/lib/*.a "$work/out/lib/"
# only the public C API headers are needed.
for h in JavaScript.h JSBase.h JSContextRef.h JSStringRef.h JSValueRef.h JSObjectRef.h JSTypedArray.h WebKitAvailability.h; do
  if [[ -e "$root/include/JavaScriptCore/$h" ]]; then cp "$root/include/JavaScriptCore/$h" "$work/out/include/JavaScriptCore/"; fi
done
rm -rf "$work/x"

# the archives ship with full debug info (~850MB); strip it so linking is fast.
if command -v strip >/dev/null 2>&1; then
  for a in "$work"/out/lib/*.a; do strip -g "$a" 2>/dev/null || true; done
fi

echo "[jsc-nim] fetching mimalloc ${mimalloc_commit}" >&2
mkdir -p "$work/mi"
if [[ -n "${JSC_MIMALLOC_TARBALL:-}" ]]; then
  tar -xzf "$JSC_MIMALLOC_TARBALL" -C "$work/mi" --strip-components=1
elif download "$mimalloc_url" "$work/mimalloc.tar.gz" && tar -tzf "$work/mimalloc.tar.gz" >/dev/null 2>&1; then
  tar -xzf "$work/mimalloc.tar.gz" -C "$work/mi" --strip-components=1
elif command -v git >/dev/null 2>&1; then
  rm -rf "$work/mi"
  git clone -q https://github.com/oven-sh/mimalloc "$work/mi"
  git -C "$work/mi" checkout -q "$mimalloc_commit"
else
  echo "[jsc-nim] could not download mimalloc" >&2
  exit 1
fi
mkdir -p "$work/out/mimalloc"
mv "$work/mi/src" "$work/mi/include" "$work/out/mimalloc/"

printf 'webkit=%s\nmimalloc=%s\narch=%s\nlibc=%s\n' "$webkit_version" "$mimalloc_commit" "$arch" "$libc" > "$work/out/VERSION"
echo "this directory is managed by jsc-nim and may be deleted and re-downloaded." > "$work/out/.jsc-nim-cache"

if ! is_ours "$dest"; then
  echo "[jsc-nim] refusing to replace $dest: it exists and was not created by jsc-nim" >&2
  exit 1
fi
rm -rf "$dest"
mv "$work/out" "$dest"
echo "[jsc-nim] done: $dest" >&2
