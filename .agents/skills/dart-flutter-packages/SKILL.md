---
name: dart-flutter-packages
description: Use when editing, validating, or diagnosing packages in the dart_flutter_packages monorepo. The agentic harness product lives in ~/xs/ecsai_harness and is not maintained from this skill.
---

# dart_flutter_packages working guide

[Root AGENTS.md](../../../AGENTS.md) is the entrypoint. Read the affected
package's `AGENTS.md` before editing. Skill Steward owns the operational map.

The agentic harness product (engine, host, workspace, AFM composition) is
`~/xs/ecsai_harness`. Inference packages and shared contracts stay here.
Do not reintroduce a dependency from a provider package onto the harness.

## Validation

From the repository root, name the package. The Justfile defaults to
`xsoulspace_inference_core` when the argument is omitted.

```bash
just check xsoulspace_inference_core
just analyze-one <package>
just test-one <package>
```

Record a baseline before editing a package that already has failing tests.
Do not treat a pre-existing failure as permission to add another.

## Conventions

- `steward map` shows the operational desk. Package gates are
  `steward action <pkg>.analyze` and `steward action <pkg>.test`.
- Classify `north_star_impact` before a durable structural change.
  `amends` / `conflicts` need an ADR first.
- Provider packages implement `InferenceClient`. They do not host daemon,
  runner, or ACP policy.

## The MLX-native engine lane (ADR 0057/0058)

`xsoulspace_inference_mlx_native` is the ENGINE HOST (one Rust cdylib +
model drivers: laya decision op-chain, Qwen3, LFM2/LFM2.5);
`xsoulspace_inference_laya` is only the laya decision product. Engine
changes never land in the laya product or in
`xsoulspace_inference_mlx` (the Swift lane is benchmark/reference only).

- Unified use: `MlxNativeTextClient.loadLfm2()/loadQwen()` binds a loaded
  engine as `InferenceClient` (template+EOS cast, greedy, tools render).
  The LAZY casts (`lazyLfm2()/lazyQwen()`) defer the weight load to
  `load()` — composition never blocks, unavailability is a typed
  retryable failure, and `unloadEngine()` frees the weights (ADR 0059).
  Requests carry `messages` (real conversation render), request-level
  `thinking`, `maxTokens`, `temperature`; core composes them through
  `GenerationOptions`/`ChatMessage`/`copyWith` (ADR 0059).
- Harness: the `lfm`/`qwen` palette entries bind through afm's
  `lfmTextBinding()/qwenTextBinding()` (lazy, env knobs
  `HARNESS_*_SNAPSHOT`, `HARNESS_*_ENGINE=off`, `HARNESS_QWEN_THINKING`);
  Last Answer exposes them as RUNTIME chips (macOS only).
- The Swift lane left the product graphs (ADR 0060): afm and LA no longer
  depend on `xsoulspace_inference_mlx`, and its hook never writes the
  shared `.dart_tool/lib/mlx.metallib` (the crossed-pair incident).
  `pin_metallib_colocated` probes candidates for a real MLX kernel
  before pinning.
- Wire use: `dart run tool/serve_text.dart` in the engine package serves
  the OpenAI-compatible loopback (default cast LFM2.5 template+EOS).
- Gates (sandbox OFF — dart build hooks hang under the sandbox):
  `just analyze-one/test-one xsoulspace_inference_mlx_native`,
  `cargo test --release` in `native/mlx_native`, `tool/test_fresh.sh`
  (63/63 golden @ 0.0 / 1.5e-8). Bench:
  `tool/model_bench_suite.dart` (lanes chat/decompression/swe/tools/laya;
  scorecards cite power state; thresholds pinned in ADR 0057).
- New architecture = Rust port + venv-recorded parity fixture. Never
  weaken an oracle; special-token ids come from the checkpoint's own
  tokenizer, never hardcoded.
- Perf-timing gates in `native/mlx_native` are AC-calibrated: on battery
  (throttles 4-10×) or under heavy load they fail WITHOUT a code defect —
  record the power state, rerun on AC, never weaken the threshold.
