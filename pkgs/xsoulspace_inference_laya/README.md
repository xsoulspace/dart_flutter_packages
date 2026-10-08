# xsoulspace_inference_laya

Local **Laya** decision-model composition for
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

## The native model runtime (default, no Python at all)

`NativeLayaDecisionEngine` runs the REAL `aac6fef/laya-mlx` checkpoint
(ModernBERT-large F16 + decision/scoring/action heads) on Apple-silicon MLX
through a Rust-hosted mlx-c cdylib wired with Dart native assets
([ADR 0051](../../../docs/decisions/0051_mlx_c_rust_engine_and_model_mesh.md)):

- `hook/build.dart` builds `native/laya_rust` (cargo; statically links the
  pinned mlx 0.32.2 + mlx-c sources) and registers the cdylib as a code asset
  with the same five `laya_native_*` symbols the Dart side has always bound —
  the first build needs the Rust toolchain, cmake, and the Metal Toolchain
  (`xcodebuild -downloadComponent MetalToolchain`) for the one-time mlx
  kernel compile. Without them the package still analyzes and its scripted
  tests pass; the golden test skips with that reason.
- Weights: `LAYA_MODEL_DIR` or `~/.cache/xsoulspace/laya-mlx` — fetch
  `aac6fef/laya-mlx` from Hugging Face (~842 MB FP16). The runtime never
  downloads anything by itself.
- Parity: `test/laya_native_golden_test.dart` reproduces the pinned
  laya-mlx runtime's outputs for the 16 reference parity cases — 63/63
  argmax, max probability error 0.0026 (FP16). The fixture and its gates are
  unchanged by the engine swap; the golden test is the acceptance oracle.
- The daemon (`harnessd` in ecsai_harness) serves this engine by default
  on a loopback `LayaDecisionServer`; `HARNESS_LAYA_ENGINE=off` reverts to
  attach-only.

The model port mirrors `laya_mlx/model.py` (github.com/mizorewww/laya-mlx,
Apache-2.0); see NOTICE for attribution. The historical Swift + mlx-swift
implementation of the same port remains documented in git history and stays
the reference route for iOS (CMake-based consumers cannot yet build an
iOS-compatible mlx metallib — ml-explore/mlx#3915).

## Setup: pure Dart first, Python only for the trained weights

**No Python is needed to run the decision path.** This package ships a
laya-compatible System One server in pure Dart:

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
attaches here later without touching clients or the harness. The harness
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
  parity fixture. The wire, bounds, cancellation, and failure mapping are
  fixture-tested against a fake server; accuracy, latency, and calibration
  are upstream properties (see the `laya-mlx` validation report) and remain
  unmeasured here.
- No GGUF, MoE, vision/audio, training, or continuous batching. The engine
  hosts laya's forward pass; the Qwen decode lane is a separate future ADR
  ([ADR 0051](../../../docs/decisions/0051_mlx_c_rust_engine_and_model_mesh.md)
  evidence ladder, L5).
- No iOS or Android on-device inference in this phase: phones join the mesh
  as participants with routing to an inference host (capability-gated
  hosting is future work).
