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
# ctfconvert/ctfmerge only translate DWARF -> CTF, so a current dtrace
# checkout is fine even though the kernel is 7195 (macOS 11.2 vintage).
# The macos-112 manifest pin is 4 years older, predates the xcodebuild
# targets blacktop's CI uses, and historically only had internal build.com
# scripts — so we build the *current* tag. Solver script for future work.
BIN_DIR="$BUILD_ROOT/dtrace/dst/usr/local/bin"
DTRACE_DIR="$BUILD_ROOT/dtrace-src"
if [ ! -d "$DTRACE_DIR" ]; then
  git clone -q --depth 1 https://github.com/apple-oss-distributions/dtrace.git "$DTRACE_DIR"
fi

pushd "$DTRACE_DIR" > /dev/null
env LD="$(xcrun -find clang)" LDPLUSPLUS="$(xcrun -find clang++)" \
  xcodebuild install -sdk macosx -target ctfconvert -target ctfdump -target ctfmerge \
  ARCHS="x86_64" CODE_SIGN_IDENTITY="-" \
  OBJROOT="$BUILD_ROOT/dtrace.obj" SYMROOT="$BUILD_ROOT/dtrace.sym" DSTROOT="$BUILD_ROOT/dtrace/fakeroot"
popd > /dev/null

mkdir -p "$BIN_DIR"
for tool in ctfconvert ctfmerge; do
  bin="$(find "$BUILD_ROOT/dtrace/fakeroot" -name "$tool" -type f 2>/dev/null | head -1)"
  [ -z "$bin" ] && { echo "could not locate built $tool" >&2; exit 1; }
  cp "$bin" "$BIN_DIR/"
done

ls -la "$BIN_DIR" | head -5
echo "sdk-7195-ios + ctf tools ready"
