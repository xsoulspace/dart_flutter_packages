#!/bin/bash
# Fresh-cycle golden test: rebuild the Rust engine, wipe ALL hook-runner
# caches for the package (both cache layers), run the golden test once.
# Usage: tool/test_fresh.sh [env VAR=VAL ...]  (env is forwarded to dart)
set -e
L="/Users/antonio/xs/storage_problem/dart_flutter_packages/pkgs/xsoulspace_inference_laya"
W="/Users/antonio/xs/storage_problem/dart_flutter_packages"
cd "$L/native/laya_rust"
echo "== cargo build"
cargo build --release 2>&1 | grep -E '^error' && exit 1 || true
echo "target: $(md5 -q target/release/liblaya_native.dylib | cut -c1-8)"
rm -rf "$W/.dart_tool/hooks_runner/xsoulspace_inference_laya" \
       "$W/.dart_tool/hooks_runner/shared/xsoulspace_inference_laya"
cd "$L"
echo "== dart test (eager)"
env "$@" dart test test/laya_native_golden_test.dart 2>&1 | grep -E 'agreements|parity|MLX error|Some tests|All tests' | head -5
echo "== dart test (LAYA_COMPILE=1 — R1 fused, ADR 0054)"
env "$@" LAYA_COMPILE=1 dart test test/laya_native_golden_test.dart 2>&1 | grep -E 'agreements|parity|MLX error|Some tests|All tests' | head -5
