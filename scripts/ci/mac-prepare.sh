#!/bin/bash
# macOS CI prep step for the XNU (BCM2837) kernel build.
#
# Reproduces the manual environment the reference project's
# tools/build_xnu_7195.sh expects:
#   - build/xnu-latest-build/sdk-7195-ios/iPhoneOS.sdk   (SDK copy)
#   - build/xnu-latest-build/dtrace/dst/usr/local/bin/{ctfconvert,ctfmerge}
#
# The reference repo documents "no script in this repo creates that SDK
# copy" — this script is our compensation so CI is hermetic.

set -euo pipefail

HUB="$1"          # path to the reference hub checkout (contains tools/)
MACOS_MANIFEST="${MACOS_MANIFEST:-macos-112}"
cd "$HUB"

BUILD_ROOT="$PWD/build/xnu-latest-build"
mkdir -p "$BUILD_ROOT/sdk-7195-ios" "$BUILD_ROOT/dtrace/dst/usr/local/bin"

# ---- 1. iPhoneOS SDK copy ---------------------------------------------------
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "Using SDK: $SDK_PATH ($(xcrun --sdk iphoneos --show-sdk-version))"
SDK_DIR="$BUILD_ROOT/sdk-7195-ios/iPhoneOS.sdk"
rm -rf "$SDK_DIR"
cp -a "$SDK_PATH" "$SDK_DIR"

# ---- 2. ctf tools from Apple dtrace -----------------------------------------
# dtrace tag must come from the same manifest vintage as xnu-7195 (macOS 11.2).
DTRACE_TAG="$(python3 -c '
import json, urllib.request, sys
urls = [
    "https://raw.githubusercontent.com/apple-oss-distributions/distribution-macOS/'"$MACOS_MANIFEST"'/manifest.json",
]
data = None
for u in urls:
    try:
        data = json.load(urllib.request.urlopen(u, timeout=30))
        break
    except Exception:
        pass
if not data:
    sys.exit("could not fetch manifest")
entry = data.get("dtrace") or data.get("Dtrace")
if isinstance(entry, dict):
    entry = entry.get("tag") or entry.get("version")
print(entry)
')"
echo "Using dtrace tag: $DTRACE_TAG"

DTRACE_DIR="$BUILD_ROOT/dtrace-src"
if [ ! -d "$DTRACE_DIR" ]; then
  git clone -q --depth 1 --branch "$DTRACE_TAG" \
    https://github.com/apple-oss-distributions/dtrace.git "$DTRACE_DIR"
fi

BIN_DIR="$BUILD_ROOT/dtrace/dst/usr/local/bin"
pushd "$DTRACE_DIR" > /dev/null
# Apple dtrace's top-level make builds the ctf tools into the repo-relative
# dst/ tree; fall back to explicit per-tool build if needed.
( make -j 3 || true )
for tool in ctfconvert ctfmerge; do
  bin=""
  for cand in "$PWD/dst/usr/local/bin/$tool" "$PWD/tools/$tool/obj/$tool" "$PWD/tools/$tool/$tool"; do
    [ -x "$cand" ] && bin="$cand" && break
  done
  if [ -z "$bin" ]; then
    ( make -C "tools/$tool" || true )
    for cand in "$PWD/tools/$tool/obj/$tool" "$PWD/tools/$tool/$tool" "$PWD/$tool"; do
      [ -x "$cand" ] && bin="$cand" && break
    done
  fi
  [ -z "$bin" ] && { echo "could not build $tool" >&2; exit 1; }
  cp "$bin" "$BIN_DIR/"
done
popd > /dev/null

ls -la "$BIN_DIR" | head -5
echo "sdk-7195-ios + ctf tools ready"
