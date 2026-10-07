# xsoulspace_inference_mlx

A **local small generative text model** (MLX on Apple Silicon) bound as an
`xsoulspace_inference_core` `InferenceClient` — the text-generation sibling
of the laya local decision provider.

## Shape

- `MlxServeRuntime` — the shared health-gated loopback serve skeleton
  (`xsoulspace_inference_local_serve`) with MLX defaults: attach to an
  already-running `mlx_lm.server`, or spawn it on miss (explicit opt-in),
  health deadline sized for a cold model load, honest readiness snapshots.
- `MlxLocalTextClient` — `InferenceClient` over the OpenAI-compatible chat
  wire (`/v1/chat/completions`). Plain `InferenceTask.text` only; greedy
  decoding by default; typed unavailable when detached.
- `FakeMlxChatServer` / `ScriptedMlxChatEngine` — pure-Dart wire fake on the
  shared `LoopbackJsonServer` skeleton; the whole client path is testable
  with no Python runtime and no model weights.
- `NapDraftPrompts` / `NapDraftRecord` / `NapDraftStore` — the nap-drafting
  contract: provenance-stamped drafts in a review-only sidecar queue.

## Hard laws

- **Derived only.** The model drafts summaries and annotations; it never
  writes raw records. Drafts apply only through the reviewer-run `nap`
  command — the same validated, provenance-linked write path the tool
  itself uses.
- **Nothing model-driven in any read path.** Wake/orient/find stay
  deterministic (ADR 0079). The drafts queue is a review worklist nothing
  reads to answer questions.
- **No egress.** Loopback only. The runtime never installs or downloads;
  the operator chooses the model and starts (or opts into spawning) the
  server.
- **Content-free diagnostics.** Wire events carry byte counts, statuses,
  and durations — never prompt text, memory records, or completions.

## Model choice (2026-10)

Primary: `LiquidAI/LFM2.5-1.2B-Instruct-MLX-4bit` (LFM Open License v1.0 —
Apache-derived with a <$10M commercial-revenue condition; weights are a
local operator download, never redistributed by this repo). Alternate:
`mlx-community/Qwen3-1.7B-4bit` (Apache-2.0; run with thinking mode off).
See `tool/` in the consuming lane for the benchmark ledger.
