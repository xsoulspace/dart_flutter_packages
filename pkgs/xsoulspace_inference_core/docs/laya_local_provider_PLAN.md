# Laya local decision provider — delivery plan

Updated: 2026-10-07. L0–L4 and the harness binding **landed** on this date;
the boundary non-claims at the end remain true. `north_star_impact: applies`
— new provider packages and additive contract fields; no core-center change
beyond what [ADR 0038](../../../../../ecsai_harness/docs/decisions/0038_optional_decision_providers.md)
already fixed (decision providers stay optional, vendor-replaceable, outside
harness core). The generic capability plan is
[decision_provider_PLAN.md](decision_provider_PLAN.md); the hosted pilot is
[jev_pilot_PLAN.md](../../xsoulspace_inference_openrouter/docs/jev_pilot_PLAN.md).

## L0 — Verified model facts (2026-10-07)

Checked against Hugging Face and the upstream repository; recheck before
relying on numbers.

- [`convaiinnovations/laya`](https://huggingface.co/convaiinnovations/laya)
  — Apache-2.0 open-weights **System One decision model**: multilingual,
  non-autoregressive (ModernBERT-large, 421M params, 512-token context,
  ~33 ms per question on a T4, 7.2 ms/question batched). Answers typed
  `choice` / `score` / `noul` questions with calibrated probabilities
  (RLCD training against proper scoring rules). Siblings:
  `laya-multilingual` (mmBERT-base, 322M, 1024–8192 tokens, 100+ languages)
  and `laya-typed-decisions`.
- Runtimes: `pip install laya` (with `laya[serve]` HTTP server),
  [`aac6fef/laya-mlx`](https://huggingface.co/aac6fef/laya-mlx) (MLX FP16
  conversion for Apple silicon; ModernBERT-large + laya decision/scoring/
  action heads; macOS 14+), and [`ggml-org/Laya-GGUF`](https://huggingface.co/ggml-org/Laya-GGUF)
  (llama.cpp quantizations).
- Server wire: `laya-serve` binds `127.0.0.1` port **8000** by default,
  serves `GET /health` (open) and `POST /v1/systemone` (Jev-compatible
  body: `model` + `state` + `questions{id: {type, instructions, criteria}}`;
  optional `Bearer` auth via `LAYA_API_KEY`; `LAYA_JEV_STRICT` projects
  onto the strict Jev contract).

## What landed (L1–L4 + harness)

### L1 — core: first-class generation params

`InferenceRequest` gained optional `maxTokens`, `temperature`, and
`stopSequences` (`max_tokens` / `temperature` / `stop_sequences` on the
wire-neutral map). Absent params never serialize as explicit nulls, so old
payloads decode unchanged. Providers with a **required** budget (Anthropic
`max_tokens`) reject absent budgets with the named code `missing_max_tokens`
instead of inventing provider defaults.
Gate: `just check xsoulspace_inference_core` — green (66 tests).

### L2 — openrouter: shared System One wire + local-server adapter

The transport machinery of `OpenRouterSystemOneDecisionProvider` (validate →
dispatch → bounded retry → typed failure → strict parse via
`validateDecisionCompletion`, adapter-enforced cancellation) moved verbatim
into `SystemOneWireDecisionProvider`; the OpenRouter adapter is now a thin
subclass and its existing suite passed unchanged (the acceptance oracle).

New in the same package:

- `LayaServerDecisionProvider` (`laya_server.dart` entrypoint) — the System
  One wire against a laya-compatible server, defaulting to the documented
  `http://127.0.0.1:8000/v1/systemone`. Capability facts are honest:
  `executionLocation: local`, `networkRequirement: none` (loopback socket
  traffic is not external egress). Auth optional: no credential, no
  `authorization` header. Answer `confidence` is optional on this wire
  (`LAYA_JEV_STRICT` restores it). Only `choice` questions cross the wire in
  v0; `score`/`noul` wait for neutral question kinds.
- `LayaServerReadinessProbe` — one-shot `GET /health`.
- Conformance fixtures mirror the D2 list against a mock server: bounds
  before dispatch, unknown/invented answers, malformed JSON, correlation
  ownership, cancellation before/during flight, late-response discard,
  dispose, single-use cancellation IDs, 401/503 mapping, bounded retries,
  diagnostic capture without credentials.
  Gate: `just check xsoulspace_inference_openrouter` — green (57 tests).

### L3 — anthropic: the Messages wire family

New package `xsoulspace_inference_anthropic`: `AnthropicInferenceClient`
implements `InferenceClient` against `POST /v1/messages` (`x-api-key` +
`anthropic-version` headers, top-level `system`, content blocks, native
`tool_use` → `ToolCall` records). Requires explicit `maxTokens`; passes
`temperature` / `stop_sequences`; renders context fragments into a native
multi-turn `messages` array via `SituationMessagesCodec`. The shared
`SchemaBundle` → JSON-Schema conversion moved into core
(`bundleToJsonSchema`) now that a second wire family needs it; the
OpenRouter public API delegates.
Gate: analyze clean, 11 tests green.

### L4 — laya: local runtime composition (macOS today)

New package `xsoulspace_inference_laya`:

- `LayaServeRuntime` — attach-or-spawn lifecycle for a local laya-serve
  (health polling with early-exit detection). Attach-only by default;
  spawning is an explicit opt-in and the runtime kills only what it spawned.
- `LayaLocalDecisionProvider` — `DecisionProvider` with `id: laya_local`,
  composing the loopback wire adapter with runtime readiness; a detached
  server surfaces as typed `DecisionUnavailable`. Bind it wherever a hosted
  decision provider binds; local-only policy admits it through capability
  facts alone.
  Gate: analyze clean, 8 tests green (faked process/health seams).

### Harness — composition-root binding

`xsoulspace_agentic_afm` gained `layaDecisionBinding` (`laya_binding.dart`),
reusing `JevClientBinding` budgets/diagnostics/handler composition with the
local provider and a distinct `laya-decision` router id (the binding now
takes `routerModelId` additively; jev defaults unchanged). Local laya for
the System One lane; hosted Jev as overflow; chat families (AFM local,
Anthropic, OpenRouter) for prose/escalation roles — the J1-M mixed-actor
shape.
Gate: `flutter test test/laya_binding_test.dart test/jev_binding_test.dart
test/jev_diagnostics_test.dart` — green; pre-existing `tool/` analyzer
findings unchanged (baseline).

## Second increment (2026-10-07): the pure-Dart wire server

Antonio's correction: the **server** side needs no Python either. Dart has
native hooks, and we just built the API in Dart — so the wire got a Dart
twin in the laya package:

- `LayaDecisionServer` — a laya-compatible System One server in pure Dart
  (`GET /health` open, `POST /v1/systemone` with optional bearer auth,
  responses normalized into the strict shape our clients validate). Binds
  loopback, ephemeral port by default.
- `LayaDecisionEngine` — the seam that answers. `ScriptedLayaDecisionEngine`
  pins answers by question id against wire descriptions (the same semantics
  the harness fixtures use); a real model runtime can attach here later
  through Dart native assets without touching clients or the harness path.

New end-to-end proof — `xsoulspace_agentic_afm/test/laya_wire_integration_test.dart`:
the canonical host decision handler (workspace domains, ADR-0042 batching,
budgets) drives a ten-row `opChain` through `layaDecisionBinding` over the
loopback Dart server to a real tool execution, and the server observes
exactly `binding.providerCalls` requests — every host decision crossed the
wire. Wired declaratively as harness lane `laya-integration`
(`tool/laya_integration_lane.dart`, launched by `tool/hot_laya_integration.sh`;
the one-shot CI gate is the same test command). Lane smoke: ready →
`command_receipt ok:true` in 12.3 s.

Consequence: the whole integration path — clients, binding, handler,
server, tests, lane — is Python-free. The trained checkpoints remain
external (see non-claims).

## Measured performance (2026-10-07, first record)

`benchmark/laya_benchmark.dart` in the laya package (loopback, scripted
engine, deterministic; min 200 ops / 3 s per scenario). Machine: Apple
Silicon macOS 26, Dart 3.13.4. JIT = `dart run`, AOT = `dart compile exe`.

| scenario | JIT | AOT |
| --- | --- | --- |
| engine.answer (16q × 8 options) | 731k ops/s | 650k ops/s |
| wire POST /v1/systemone (16q, keep-alive) | 2,958 req/s, p50 0.28 ms | 3,729 req/s, p50 0.22 ms |
| provider.decide (1 question) | 5,391/s, p50 0.16 ms, p99 0.50 ms | 6,653/s, p50 0.14 ms, p99 0.31 ms |
| provider.decide (16 questions) | 1,316/s, p50 0.63 ms | 1,708/s, p50 0.55 ms |
| questions/s through the validated provider path | ~21k | ~27k |

Framing: the full Dart stack (HTTP + strict validation + normalization)
costs ~0.15–0.6 ms per decision — single-digit percent of even the fastest
measured model inference (upstream reports ~33 ms per laya question on a
T4, ~13 ms MLX Apple Silicon). The wire is not the bottleneck; engine-only
ceiling is >10M questions/s. Numbers are machine-relative; re-record with
`dart run benchmark/laya_benchmark.dart` when hardware or the wire changes.

## Third increment (2026-10-07): the native model runtime (laya-mlx via
## Dart native assets)

The `LayaDecisionEngine` seam now has a REAL model engine: the
`aac6fef/laya-mlx` checkpoint (ModernBERT-large F16 + decision/scoring/action
heads) runs on Apple-silicon MLX behind a Swift dylib that Dart reaches
through `dart:ffi` native assets — no Python anywhere in the path.

- **`xsoulspace_inference_laya/native/laya_native`** — a Swift package
  (mlx-swift 0.32) porting `laya_mlx/model.py` op-for-op: embedding norm,
  28 alternating full/sliding RoPE layers (boolean keep-masks, padded
  queries see valid keys), gated MLP (gelu on the value chunk), the
  pre-norm decision head with ReLU feed-forward (PyTorch
  `TransformerEncoderLayer` default), scorer, action head, float32 logits.
  A C ABI (`laya_native_load/forward/free/unload/normalize`) carries JSON
  batches in, logits out; NFC normalization rides the same dylib.
- **`hook/build.dart`** — Dart native-assets build hook: builds the SPM
  package, registers the dylib as a code asset (`@Native(assetId:)`), and
  colocates MLX's metallib beside every load candidate (mlx resolves its
  kernels next to the loaded dylib; a bare dart process has no SwiftPM
  bundle, so the loader path is pinned at load time via dladdr). Honest
  degradation: without the Apple toolchain (swiftc + Metal Toolchain) the
  hook registers no asset and says so; the golden test skips.
- **Dart side owns everything around the model**: `LayaByteLevelTokenizer`
  (GPT-2 byte-level BPE from `tokenizer.json`, pair-array merges, added
  tokens, NFC via the dylib), `laya_prompt.dart` (typed
  choice/score/noul prompt building + Python-fidelity JSON rendering and
  temperature buckets with the laya-mlx honesty clamp [0.5, 5.0]), and
  `NativeLayaDecisionEngine` (batching, calibration, the
  `LayaDecisionEngine` seam).
- **Fidelity (the oracle is the reference runtime itself)**: the golden
  fixture (`test/fixtures/laya_golden_fp16.json`) records the pinned
  laya-mlx runtime's outputs for the 16 parity cases on this machine; the
  test reproduces **63/63 argmax agreements with max probability error
  0.0026** (FP16, tolerance bar 0.005). Sequence lengths match the
  reference token-for-token.
- **Harness**: `harnessd` composes the engine by default — it serves a
  loopback `LayaDecisionServer` with the native engine and binds the laya
  palette entry to it (`HARNESS_LAYA_ENGINE=off` falls back to
  attach-only for an external laya-serve). Boot line reports the endpoint
  and load time; a missing dylib or weights degrades honestly to
  attach-only.
- **Measured (2026-10-07, clean machine)**: 3-question email batch ≈
  **167 ms p50 / 177 ms p99** — identical JIT and AOT (`dart run` vs
  `dart build cli` bundle; ~55 ms per question, model inference
  included). Earlier larger numbers (264–486 ms) were machine-load
  artifacts from concurrent test gates. Upstream reports ~13 ms/decision
  on M3 Max with `mx.compile`; the optimization lane (compile, padding
  policy) is open and does not affect parity.
- **AOT delivery** (2026-10-07): `dart compile exe` in SDK 3.13.4 does
  not bundle code assets (silently — no warning); the blessed path is
  **`dart build cli`**, which runs the hooks and copies the dylib into
  `bundle/lib/`. Two deployment shapes are proven:
  1. `dart build cli` bundle — the metallib comes from the fleet cache
     via the pin's fallback chain (the builder bundles only code assets
     in this SDK, so ship `mlx.metallib` beside `bundle/lib/` for a
     self-contained bundle);
  2. `dart compile exe` + `liblaya_native.dylib` and `mlx.metallib` in
     `<exe-dir>/lib/` — the engine preloads the dylib through
     `DynamicLibrary.open` (probe-retry: no preload when the native-assets
     manifest resolves, so the library is never loaded twice) and the
     metallib pin resolves beside the loaded dylib.
  The hook refreshes the fleet cache (`~/.cache/xsoulspace/laya/native/`)
  with both files, which is the deploy-free load location.
- Weights: `LAYA_MODEL_DIR` or `~/.cache/xsoulspace/laya-mlx` (fetch
  `aac6fef/laya-mlx`; the runtime never downloads). License Apache-2.0;
  attribution in the laya package NOTICE file.

## Non-claims

- **Model quality is the checkpoint's, not ours.** The native port is
  validated for agreement with the laya-mlx runtime (argmax + calibrated
  probabilities above); accuracy, calibration honesty, and task fit remain
  upstream properties. The hosted Jev pilot's evidence rules
  ([jev_pilot_PLAN.md](../../xsoulspace_inference_openrouter/docs/jev_pilot_PLAN.md))
  apply to any capability claims about the model's decisions.
- **`LayaDecisionServer` with the scripted engine is still a wire server,
  not a model.** The scripted engine remains the default for tests; usage
  counts are estimates there. With `NativeLayaDecisionEngine` attached the
  server serves real model decisions (that is the harness default when
  artifacts are present), and token counts become measured inputs.
- **The native runtime is macOS/Apple-silicon only** (MLX + Metal
  Toolchain). Other hosts keep the attach-only story (`laya-serve`).
  AOT: `dart build cli` is the supported application shape; `dart
  compile exe` needs the dylib + metallib shipped beside the executable
  (the engine preloads them) — see the AOT delivery note above.
- The native benchmark numbers are a first record, not a target: no
  `mx.compile`, naive padding; latency work is an open lane.
- `score` and `noul` question kinds are not ON THE WIRE in the neutral
  contract yet (the model runs them through the typed engine path; the
  harness wire serves choice).
- SSE streaming for Anthropic is not implemented; the client is
  request/response only.

## API-family FAQ

Why three families and where each lives — see the Design FAQ section
["Why three wire families"](DESIGN_FAQ.md).
