#!/bin/sh
# Builds the native bridge dylib (macOS, arm64).
#
# Usage: sh tool/build_bridge.sh
# Output: build/libxs_fm_bridge.dylib
set -e

cd "$(dirname "$0")/.."

SRC="bridge/src/bridge.swift bridge/src/DartSchemaMaterializer.swift"
OUT_DIR="build"
OUT="$OUT_DIR/libxs_fm_bridge.dylib"

mkdir -p "$OUT_DIR"

SDK="$(xcrun --show-sdk-path)"
MIN_MACOS="26.4"

swiftc \
  -emit-library \
  -o "$OUT" \
  -target arm64-apple-macos$MIN_MACOS \
  -sdk "$SDK" \
  -framework FoundationModels \
  -parse-as-library \
  $SRC

echo "Built $OUT"
