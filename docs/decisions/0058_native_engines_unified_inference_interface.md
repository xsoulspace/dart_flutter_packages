# ADR 0058: The native engines join the unified inference interface

Date: 2026-10-09
Status: Accepted and executed (2026-10-09)
Related: 0051 (engine), 0055 (LFM2/qwen rungs), 0056 (landscape),
0057 (engine-host refactor; R3 shim drop executed alongside this ADR)

## Context

The owner directive: update docs and skills, and unify the API — the
monorepo already funnels remote AND local model usage through
`xsoulspace_inference_core` (`InferenceClient`,
`ProvisionableInferenceClient`, readiness, results), and the local native
engines should be reachable through it like every other provider.

Verified gap: the engine host (`xsoulspace_inference_mlx_native`,
ADR 0057) exposes only its bespoke surface — `NativeQwenTextEngine` /
`NativeLfm2TextEngine` (FFI clients) and `LayaQwenChatServer` /
`LayaLfm2ChatServer` (loopback wire). General consumers must either
speak engine-specific classes in-process or attach to a served wire.
The Swift lane already shows the target shape: `MlxLocalTextClient`
(`xsoulspace_inference_mlx`) binds a chat endpoint to
`InferenceClient`. The Rust production line — the line ADR 0057 made
the ONLY production serving path — has no core binding at all.

Convention evidence: the inference family is provider-implements-core
(`xsoulspace_inference_core` is dependency-free; every provider package
depends on it and implements `InferenceClient`). The engine host
violates the convention by implementing nothing.

## Decision

### 1. The engine host implements `InferenceClient` directly

`xsoulspace_inference_mlx_native` takes the
`xsoulspace_inference_core` path dependency and gains
`MlxNativeTextClient` (`lib/src/mlx_native_text_client.dart`):

- One client class serves both drivers. A loaded engine
  (`NativeQwenTextEngine` or `NativeLfm2TextEngine`) plus a
  `MlxNativeCast` (engine kind, template on/off, thinking flag) is the
  constructor surface; the cast renders the request through the
  checkpoint's fixture-gated chat template and stops at its EOS ids —
  exactly the bench's winning cell (template+EOS), which is the
  production default, not an option callers must discover.
- Dispatch rides `generateAsync` (the isolate escape), so a decode
  never blocks the caller. The native engines decode greedily; a
  non-zero request `temperature` lands in `InferenceResult.warnings`
  (honest non-claim), never silently pretended.
- Availability is the loaded-engine snapshot (getters do no I/O);
  `load()`/`refreshAvailability()` are idempotent no-ops on an
  already-loaded engine (loading happens at construction, like the
  Swift lane's `NativeMlxTextEngine.load`).
- Capability facts mirror `MlxLocalTextClient`'s honesty: `id` names
  the cast (e.g. `mlx_native_lfm2`), locality law unchanged, only
  `InferenceTask.text` supported, structured output stays the caller's
  prompt contract.

Why IN the engine package (not a glue package): the provider
convention puts the core binding next to the provider; a glue package
would re-create the detached-adapter layering ADR 0057 removed.

### 2. ProvisionableInferenceClient is NOT adopted (non-claim with a reason)

`ensureReady`'s contract is purpose→artifact provisioning (download
consent, quotas, progress UI). The engine runtime NEVER downloads
(ADR 0055 law), and purpose→checkpoint mapping is product policy —
the engine host knows no product (ADR 0057). The client takes an
explicit loaded engine; a product-level composition (the mlx package's
runtime shape) is where provisioning belongs if a consumer needs it.

### 3. The three consumption paths (docs; README + skill updated)

1. **In-process, unified** — `MlxNativeTextClient` (this ADR): the
   lowest-latency path; native assets make it available to any Dart
   process that can load the dylib (`dart run`/`dart test`; NOT
   `dart compile exe` — AOT drops native assets).
2. **Wire** — `dart run tool/serve_text.dart` serves the
   OpenAI-compatible loopback; ANY HTTP client attaches (curl, the
   harness `mlx_local` attach-only client, other languages). Default
   cast flips to the measured production instruct cast (LFM2.5,
   template+EOS) with this ADR.
3. **Harness** — the daemon/afm bindings (R3: they import the engine
   package directly; the laya re-export shim is dropped with this
   ADR).

### 4. R3 executed here (ADR 0057's rung, same motion)

The laya barrel stops re-exporting the engine; harness `afm` and
`experiments` import `xsoulspace_inference_mlx_native` directly; laya
keeps only its product surface (decision provider, serve runtime).

## Consequences

- The unified interface now covers the production local line: a
  consumer written against `InferenceClient` casts remote providers,
  the Swift lane (wire or in-process), and the Rust engines with no
  engine-specific code.
- The engine package gains a `xsoulspace_inference_core` dependency —
  the provider direction, core stays dependency-free (verified).
- Non-claims: no temperature sampling (greedy only, warned); no
  provisioning contract in the engine host; no streaming on this
  client (the wire servers and decision server have their own
  surfaces; streaming inference is a separate contract — recorded).

## Evidence (2026-10-09)

- Dart suite in the engine package: the new client tests pass
  (cast mapping, warnings honesty, unsupported-task refusal,
  template+EOS defaults, tools pass-through where the template
  supports them); `dart analyze` clean.
- The wire proof (ADR 0057) stands unchanged; `serve_text.dart`
  default engine flipped to `lfm2` with `--thinking` exposed for the
  qwen cast.
- **Tools rung (both casts):** the Qwen3 renderer gained the fixture-gated
  `# Tools` system block, `json.dumps(ensure_ascii=False)` tool lines
  (the LFM2.5 encoder is the ensure_ascii=True variant — they differ),
  and the `tool`-role → user `<tool_response>` wrapper (consecutive-tool
  merging stays a recorded non-claim): 7/7 byte-exact fixture cases
  (tools-user-only, tools-with-system, tools-assistant-call-history,
  tools-non-ascii recorded from the reference venv). The chat server
  routes pass wire `tools` through; `MlxNativeTextClient` renders a
  `ToolRegistry` on both casts. The bench's `tools` lane (5 cases:
  name+args match, one no-tool discipline case) measured LFM2.5 5/5
  (its native signature format
  `<|tool_call_start|>[name(arg="v")]<|tool_call_end|>`, parsed
  format-tolerantly) and Qwen3-0.6B 4/5 (answers one weather case
  directly — the honest 0.6B miss). Thresholds recorded in ADR 0057.
- **R3 executed with this ADR** (ADR 0057's rung): the laya barrel
  exports only the product surface; harness afm/experiments import the
  engine package directly (seven files); gates green (afm laya tests —
  the wire integration runs the real ten-row opChain — plus analyze at
  the pre-existing infos; the 5 other afm failures are pre-existing,
  stash-proven at the pre-change state).
- **The 2.6B rung:** `mlx-community/LFM2.5-2.6B-4bit` rides the LFM2
  driver after four read-never-guess fixes: `rope_theta` resolves from
  `rope_parameters` when top-level is absent; `bos_token_id` rides
  config (124894, not the low-id 1); special ids resolve from the
  checkpoint's own tokenizer via the new `mlx_native_lfm2_special_ids`
  FFI (`im_end` 124900, `endoftext` 124895 — never carried across
  checkpoints); weights detect the `language_model.` prefix some
  mlx-community multimodal-wrapper conversions carry. Its template
  variant (`Lfm2ChatTemplateVariant.lfm25_26b`, fixture-gated 4/4
  byte-exact) opens the think block at the generation prompt; the
  server/client cut the wire answer at the model's own think close
  (no close in the output ⇒ empty answer, honestly). Load failures
  surface their real error through `mlx_native_lfm2_last_load_error`
  instead of a bare code. Bench row: see ADR 0057's scorecard section.
