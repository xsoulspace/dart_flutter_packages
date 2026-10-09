# ADR 0060: The Swift text-engine lane leaves the product graphs

Date: 2026-10-10
Status: Accepted and executed (2026-10-10)
Related: 0057 (engine-host refactor — "Swift line = bench-only"), 0058
(unified interface), 0059 (palette + lazy casts)

## Context

ADR 0057 made the Rust engine host the only production serving path and
demoted the Swift/ mlx-swift text engine (`xsoulspace_inference_mlx`,
`libMlxTextNative.dylib`) to bench/reference — but the package stayed in
the PRODUCT dependency graphs (afm's `mlx_binding.dart`, LA's override)
and its build hook kept refreshing the fleet load dirs.

Measured incident (2026-10-10, the ADR 0059 embed dogfood): both engine
packages ship their kernel library under the SAME load-dir filename
(`mlx.metallib` in the resolving workspace's `.dart_tool/lib`), and both
hooks write it last-writer-wins. The harness workspace held a CROSSED
pair — the Rust `libmlx_native.dylib` beside the Swift lane's 2.4 MB
metallib — and the first generate failed with
`MLX error: [metal::Device] Unable to load kernel arangeint32`. The pin
function (mlx_native `lib.rs`) took the first existing candidate with no
validation, so a wrong-payload file silently won.

Owner decision (2026-10-10): no parallel line owns the Swift lane
anymore — retire it from the product graphs.

## Decision

1. **One shared filename, one writer.** The `xsoulspace_inference_mlx`
   hook stops refreshing `.dart_tool/lib/mlx.metallib` (the colliding
   name). Its own Swift-dylib refresh (`libMlxTextNative.dylib` — no
   collision) and its own cache dir (`~/.cache/xsoulspace/mlx_text/`)
   stay. The Swift bench keeps resolving: colocated probe beside its
   dylib, then its own cache.
2. **mlx_native's pin probes before it trusts.** `pin_metallib_colocated`
   now verifies a candidate carries MLX's kernel library (chunked byte
   probe for `arangeint32`, a kernel MLX demands on ordinary decode
   paths) and falls through to the next candidate on a miss; only a set
   with no probed match degrades to first-existing (today's behavior).
   Defense in depth: even a future writer of the shared name cannot
   brick the engine at kernel-launch time.
3. **afm drops the old package.** `mlx_binding.dart` (the
   `MlxLocalTextClient` wire-lane binding) and its test are deleted; the
   `xsoulspace_inference_mlx` dependency is removed. The lane had no
   daemon binding and no palette entry (ADR 0059 retired the
   declaration); the Rust engine's wire form (`serve_text.dart`) plus
   the in-process casts cover every serving shape.
4. **Last Answer drops the override.** With afm clean, LA's
   `xsoulspace_inference_mlx` path override has no resolver conflict to
   answer and is removed.

## Non-claims

- The `xsoulspace_inference_mlx` PACKAGE stays in the monorepo as the
  bench/reference lane: optmem's nap-draft lane speaks the wire client
  against the NATIVE loopback server (no Swift runtime at nap time), and
  the napbench reference legs record against it. Full package deletion
  is a later ADR (it needs the optmem lane repointed to the in-process
  lazy client first — a nightly-cron lane, not a mid-goal sweep).
- No engine behavior changed beyond the pin probe; the Rust parity
  oracles are untouched.

## Evidence

All measured 2026-10-10.

- The incident: the harness workspace's `.dart_tool/lib` held
  `libmlx_native.dylib` (17.5 MB, Oct 10) beside `mlx.metallib`
  **2,401,016 bytes** (the Swift lane's, Oct 9 16:13) while the Rust
  hook output held the **140,366,772-byte** library. Kernel probe:
  `arangeint32` appears **2× in the real library, 0× in the impostor**;
  the first generate failed `MLX error: [metal::Device] Unable to load
  kernel arangeint32`. After the fixes the load dir holds the 140 MB
  library (probe: 2 hits) and the embed dogfood completes a real turn.
- `xsoulspace_inference_mlx` suite **18/18** after the hook change (the
  bench keeps its colocated + own-cache resolution);
  `xsoulspace_inference_mlx_native` cargo tests: 10/10 correctness
  (the `l0_ops_run_and_are_dispatch_cheap` timing gate failed at
  610 µs → 3102 µs on **battery power, 62%, load average 124** — the
  AC-calibrated perf gate, power-state-contaminated, not a code
  failure; never weakened).
- afm: `xsoulspace_inference_mlx` gone from the pubspec and the source
  tree (`mlx_binding.dart` + its test deleted); `dart analyze` clean;
  selection + binding suites green.
- Last Answer: the `xsoulspace_inference_mlx` override removed; the
  `xsoulspace_inference_mlx_native` path override (needed once afm's
  hosted-`any` and laya's path dep both reached the engine host)
  resolves cleanly; coding_agent/doc analyze 0 errors.
