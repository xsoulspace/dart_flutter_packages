# xsoulspace_inference_laya

Local **Laya** decision-model product composition for
[xsoulspace_inference_core](https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/xsoulspace_inference_core)
on macOS (and any host that can run a local `laya-serve`).

Laya (`convaiinnovations/laya`, Apache-2.0) is an open-weights System One
decision model: a ModernBERT-large encoder that answers typed `choice` /
`score` / `noul` questions with calibrated probabilities in a single forward
pass (~33 ms measured upstream; 7.2 ms/question batched). It never generates
text. Its `laya-serve` HTTP runtime exposes `POST /v1/systemone` — the same
wire the hosted OpenRouter System One endpoint speaks.

## What this package owns

- **`LayaServeRuntime`** — is a laya-serve answering at the health endpoint?
  Attaches to an already-running server by default; spawning one is an
  explicit `spawnOnMiss` opt-in (it never installs anything or downloads
  checkpoints, and kills only what it spawned).
- **`LayaLocalDecisionProvider`** — a `DecisionProvider` bound to the
  runtime, composing the shared System One wire adapter from
  `xsoulspace_inference_openrouter` (the wire is identical, so it is
  composed, not duplicated). Capability facts are honest:
  `executionLocation: local`, `networkRequirement: none` (no external
  egress; requests travel over loopback). A detached runtime surfaces as a
  typed `DecisionUnavailable`, never a socket error.

```dart
final runtime = LayaServeRuntime();          // attach mode
final provider = LayaLocalDecisionProvider(runtime: runtime);
if (await runtime.ensureRunning()) {
  final outcome = await provider.decide(request);
}
```

Bind it wherever a hosted decision provider would bind (the harness
`jevDecisionBinding` seam); local-only policy admits it through the
capability facts alone.

## The engine host lives in `xsoulspace_inference_mlx_native`

The MLX-native engine — the Rust cdylib (`native/laya_rust`), the
native-assets build hook, the composition API, the model drivers (the laya
decision op-chain, Qwen3, LFM2) with their Dart FFI clients and chat
servers, the `LayaDecisionServer`/`ScriptedLayaDecisionEngine` decision
seam, the golden fixtures, and the bench tooling — lives in
[xsoulspace_inference_mlx_native](../xsoulspace_inference_mlx_native)
([ADR 0057](../../../docs/decisions/0057_engine_host_refactor_and_bench_architecture.md)).

This package's barrel re-exports the engine package for one deprecation
cycle (the R2 shim), so existing
`package:xsoulspace_inference_laya/xsoulspace_inference_laya.dart` imports —
including the harness's `laya_binding` — keep compiling unchanged; R3 drops
the shim and consumers import the engine package directly. The native
engine registers as `package:xsoulspace_inference_mlx_native/mlx_native`
(crate `native/mlx_native`, dylib `libmlx_native.dylib` — the assetId debt
was resolved right after the split, ADR 0057).

The daemon (`harnessd` in ecsai_harness) serves the native laya engine by
default on a loopback decision server; `HARNESS_LAYA_ENGINE=off` reverts to
attach-only.

## Setup: pure Dart first, Python only for the trained weights

**No Python is needed to run the decision path.** The engine package ships
a laya-compatible System One server in pure Dart:

```dart
final server = LayaDecisionServer(
  engine: ScriptedLayaDecisionEngine([
    LayaDecisionPin('next_operation', 'Apply the grounded', isPrefix: true),
  ]),
);
await server.start(); // 127.0.0.1:<ephemeral>, GET /health + POST /v1/systemone
```

`LayaDecisionEngine` is the seam: today's engines are deterministic
(scripted pins matched against wire descriptions); a native model runtime
attaches here without touching clients or the harness. The harness
end-to-end proof lives in `xsoulspace_agentic_afm`
(`test/laya_wire_integration_test.dart`, wired as the declarative
`laya-integration` lane).

**For the trained checkpoints** (the real model), attach the upstream
runtime instead — macOS with Apple Silicon (Python 3.11+):

```bash
python -m pip install "laya[serve]"   # or laya-mlx for the MLX runtime
laya-serve                            # 127.0.0.1:8000, GET /health, POST /v1/systemone
```

Either server speaks the same wire: point
`LayaLocalDecisionProvider`/`LayaServerDecisionProvider` at it.

## Question kinds

Only `choice` questions cross the wire in v0 (`DecisionQuestionKind
.finiteChoice`). Laya's ordinal `score` and boolean `noul` kinds are
deferred until the neutral decision contract grows those question kinds.

## Non-claims

- No live model has been evaluated from this package beyond the golden
  parity fixture (which runs in the engine package). The wire, bounds,
  cancellation, and failure mapping are fixture-tested against a fake
  server; accuracy, latency, and calibration are upstream properties (see
  the `laya-mlx` validation report) and remain unmeasured here.
- No GGUF, MoE, vision/audio, training, or continuous batching. No iOS or
  Android on-device inference in this phase: phones join the mesh as
  participants with routing to an inference host (capability-gated hosting
  is future work).

See NOTICE for model attribution.
