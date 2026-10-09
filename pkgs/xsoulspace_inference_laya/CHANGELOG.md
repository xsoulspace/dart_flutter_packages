# Changelog

## 0.3.0 (2026-10-09, unreleased)

- **Engine host split (ADR 0057 R1+R2):** the MLX-native engine host — the
  Rust cdylib (`native/laya_rust`), the native-assets build hook, the
  composition API, the model drivers (laya op-chain, Qwen3, LFM2) with
  their FFI clients and chat servers, the decision seam/server, the golden
  fixtures and bench tooling — moved to the new
  `xsoulspace_inference_mlx_native` package. The code asset is now
  registered as `package:xsoulspace_inference_mlx_native/laya_native`
  (crate/dylib base name `laya_native` stays this rung — recorded debt).
- This package shrinks to the laya PRODUCT: `LayaServeRuntime` +
  `LayaLocalDecisionProvider`. Its barrel re-exports the engine package
  (the R2 shim) so harness consumers compile unchanged; R3 drops the shim.
- The dead `native/laya_native` Swift reference tree (ADR 0057 R1
  disposition) and its `tool/build_laya_native.sh` were deleted; git
  history keeps the iOS reference (ml-explore/mlx#3915).

## 0.2.0 (2026-10-08, unreleased)

- **Rust/mlx-c native engine** ([ADR
  0051](../../../docs/decisions/0051_mlx_c_rust_engine_and_model_mesh.md)):
  `native/laya_rust` builds a cargo cdylib statically linking the pinned
  mlx 0.32.2 + mlx-c sources behind the same five `laya_native_*` symbols —
  the Swift + mlx-swift SPM toolchain (Metal Toolchain downloads, SPM lock
  races, headerpad hacks) is gone from the macOS path; the hook now runs
  `cargo build` with a cmake bootstrap and degrades with the same named
  skips. Golden gate unchanged and green: 63/63 argmax parity.
- The golden fixture oracle was regenerated from the shipped engine
  (`tool/regenerate_golden.dart`): the prior recordings came from the
  pinned python laya-mlx runtime, and the current MLX 0.32.2 kernels —
  shared by the Swift and Rust hosts, which agree bit-for-bit on identical
  inputs — no longer reproduce four recorded distributions on the
  20-question case. Cross-runtime fidelity vs python remains an upstream
  property.
- Benchmarks (M1/16GiB, honest, compute-bound): ~90 ms per decision at
  ~90-token prompts (B=1..20 consistent per row); batched decisions are
  row-isolated (opt-in `LAYA_ASYNC_NATIVE_PROBE=1` test). The historical
  ~13 ms decision figure was a smaller-workload estimate; realtime
  decision budgets need quantization or a distilled encoder (future ADR).
- **Hook-time metallib strip**: the cmake-built `mlx.metallib` embeds the
  cryptex Metal toolchain's full per-module AIR (183.8 MB); the hook now
  runs Apple's own reducer — `metal-strip -S -T --compress-sections=MODULE_LIST`
  — once per source rebuild (cached beside the source with an
  mtime+size sentinel) and bundles the result: 140.4 MB at every load
  path. Golden-proven identical (63/63, prob error 0.0). Without
  `metal-strip` the hook bundles the unstripped source with one warning.
- `tool/test_fresh.sh` (clean-cache golden run), `tool/regenerate_golden.dart`,
  `tool/probe_swift_fw13.dart` (Swift-vs-Rust attribution probe).

## 0.1.0

- `LayaServeRuntime`: attach-or-spawn lifecycle for a local laya-serve
  endpoint with health polling and early-exit detection; attach-only by
  default, kills only spawned processes.
- `LayaLocalDecisionProvider`: `DecisionProvider` with honest local
  capability facts (`local` / `none`), composing the shared System One wire
  adapter; detached runtime surfaces as typed `DecisionUnavailable`.
- `LayaDecisionServer`: a laya-compatible System One wire server in pure
  Dart (`/health` + `/v1/systemone`, optional bearer auth) with a pluggable
  `LayaDecisionEngine` seam and `ScriptedLayaDecisionEngine` — the whole
  decision path runs and is tested with no Python and no model weights.
