#!/usr/bin/env bash
# Builds the native Laya runtime (Swift + MLX) and installs the dylib to the
# fleet cache so daemons resolve it from any working directory.
#
# Requirements: Xcode with the Metal Toolchain
# (`xcodebuild -downloadComponent MetalToolchain`), network for the first
# SPM resolve of mlx-swift.
set -euo pipefail
cd "$(dirname "$0")/../native/laya_native"
swift build -c release
mkdir -p ../../build
cp .build/release/libLayaNative.dylib ../../build/liblaya_native.dylib
mkdir -p ~/.cache/xsoulspace/laya/native
cp .build/release/libLayaNative.dylib ~/.cache/xsoulspace/laya/native/liblaya_native.dylib
echo "installed: ~/.cache/xsoulspace/laya/native/liblaya_native.dylib"
