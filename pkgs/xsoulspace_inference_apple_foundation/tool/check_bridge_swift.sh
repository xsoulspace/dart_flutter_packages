#!/bin/sh
# Compiles and runs the AFM bridge regression tests.
#
# Usage:
#   sh tool/check_bridge_swift.sh          # unit + live AFM session tests
#   LIVE=0 sh tool/check_bridge_swift.sh   # unit only (no model calls)
#
# Live tests run by default on dev machines; they cost a few seconds of
# Apple Foundation time each. They are THE regression for framework updates
# breaking NativeDartTool conformance / dynamic tool schemas
# (GenerationError -1/1020000 class).
set -e

cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
MIN_MACOS="26.4"
SRC="bridge/src/bridge.swift bridge/src/DartSchemaMaterializer.swift"
TESTS="bridge/tests/BridgeTests.swift"
OUT="build/bridge_tests"

mkdir -p build

echo "compiling..."
swiftc \
  -o "$OUT" \
  -target arm64-apple-macos$MIN_MACOS \
  -sdk "$SDK" \
  -framework FoundationModels \
  -parse-as-library \
  $SRC $TESTS

echo "running (LIVE=${LIVE:-1})..."
"$OUT"
