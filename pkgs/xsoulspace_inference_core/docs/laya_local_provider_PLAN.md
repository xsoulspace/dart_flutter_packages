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

## Non-claims

- **No live model has been evaluated from these packages.** All wire,
  bounds, cancellation, and failure behavior is fixture-tested against fake
  servers/processes. Accuracy, calibration, and latency are upstream
  properties (see the `laya-mlx` validation report) and remain unmeasured
  here. The hosted Jev pilot's evidence rules
  ([jev_pilot_PLAN.md](../../xsoulspace_inference_openrouter/docs/jev_pilot_PLAN.md))
  apply unchanged to any future Laya measurements.
- **`LayaDecisionServer` is a wire server, not a model.** Its scripted
  engine is deterministic; usage counts are estimates. The trained
  checkpoints still need `laya-serve`/`laya-mlx` (Python/MLX) or a future
  native engine on the `LayaDecisionEngine` seam. What is Python-free is
  everything around the model: the client, the server wire, the harness
  path, the tests, and the lane.
- **No in-process native MLX bridge.** A from-scratch Swift port would mean
  reimplementing laya's custom decision architecture (decision transformer,
  scoring head, action head) that the `laya-mlx` runtime owns; the
  local-server path delivers the capability today. Revisit only under
  measured constraints (e.g. embedding decisions where no Python runtime
  may run) — the engine seam above is the attach point.
- `score` and `noul` question kinds are not modeled in the neutral contract
  yet; sending them is impossible from Dart today, not silently degraded.
- SSE streaming for Anthropic is not implemented; the client is
  request/response only.

## API-family FAQ

Why three families and where each lives — see the Design FAQ section
["Why three wire families"](DESIGN_FAQ.md).
