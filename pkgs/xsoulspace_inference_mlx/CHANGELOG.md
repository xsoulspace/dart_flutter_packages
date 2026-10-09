# Changelog

## 0.1.1 (2026-10-08, unreleased)

- Hook builders wait asynchronously on a persistent SPM lock file; queued
  processes no longer fail immediately or split across deleted/recreated locks.

- **Native text lane**: `NativeMlxTextEngine` (Swift mlx-swift-lm dylib via
  native assets) — `mlx_text_load/generate/free/unload` + the loopback
  `mlx_native_chat_endpoint` / `bin/mlx_serve_native.dart`, same
  OpenAI-compatible wire as `mlx_lm.server`, no Python.
- Engine-reported facts per generation: prompt/completion token counts,
  prefill ms, decode ms, chat-template ms; requests accept `prefill_step`
  (tokens per prefill forward; nil = engine default 512) and
  `prefill_unchunked`.
- napbench text-lane tool (`tool/napbench_text_lane.dart`): cold-prefill
  TTFT at 2k/4k/8k targets, decode tok/s p50/p95, RSS, verdicts against
  the ADR 0051 acceptance table; `--warm` measures the KV-reuse lane
  shape, `--prefill-step/--unchunked` shape prefill.
- Hook: Swift sources are declared as hook dependencies up front — an
  early-return (failed swift build) used to cache an input-less result
  and never re-ran on source edits (the laya hook lesson, paid for twice).

## 0.1.0

- Initial version: local small text-model composition — `MlxServeRuntime`
  (health-gated loopback serve over the shared local-serve core,
  `mlx_lm.server` defaults), `MlxLocalTextClient` (`InferenceClient` over an
  OpenAI-compatible chat wire), `FakeMlxChatServer` + `ScriptedMlxChatEngine`
  (pure-Dart wire fake), nap-drafting prompt contracts with a refusal law,
  and provenance-stamped `NapDraftRecord`s in a review-only sidecar queue.
