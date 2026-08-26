# M5 — Real-model re-run protocol (pending credentials/device)

Everything below is runnable as-is once either (a) `OPENROUTER_API_KEY` is
set, or (b) Apple Foundation Models is unblocked on-device
(`SensitiveContentAnalysisML 1013`).

## Arms

| arm | handler | tools | family under test |
| --- | --- | --- | --- |
| baseline-write | provider native loop, whole-file writes | fs read/write/list | canonical 20 (`tasks/`) |
| ops-patch | same loop; model emits `patch_file` anchors | fs + `patch_file` (+ `verify_pack` when AE installed) | `tasks_ops/` + canonical edit/refactor |
| attribution | both arms wrapped in `AttributedHandler` | — | ledger report per run |

## Commands

```sh
# LLM-free plumbing check (seconds, no key):
cd pkgs/xsoulspace_agentic_harness && flutter test test/ops_comparison_test.dart

# Real-model ops run (OpenRouter tiny proxy), per family:
OPENROUTER_API_KEY=sk-... dart run \
  example/agents/profile_openrouter.dart --tasks benchmark/coding_suite/tasks_ops

# Canonical matrix re-run (headline table refresh):
just harness-or-bench && just a1-compare   # existing root recipes

# AFM when unblocked:
cd pkgs/xsoulspace_inference_apple_foundation && dart run bin/coding_suite_afm.dart
```

## Acceptance gates

1. Ops-arm pass rate ≥ baseline pass rate on shared tasks (no regression).
2. Generated-chars cut ≥30% sustained across the family (scripted proof:
   59.1% on refactor_patch_01).
3. Attribution table published next to pass rates — tool-result bucket must
   shrink vs the M1 first reading (14.3k/16k) or explain why not.
4. Failures remain data: JSONL traces land in `benchmark/runs/`.

## First live findings (2026-08)

Two real defects surfaced before any model comparison could run — both fixed:

1. **Silent empty successes**: OpenRouter failures (rate limit/auth/network)
   returned `data=null`, which `DefaultGenerationHandler` converted into an
   *empty but successful* answer. The loop then churned on blank turns
   (17 "answered" decisions doing nothing). Now surfaces as
   `error=backend_failed`; ledger shows `{error: N}` instead of fake answers.
2. **Model-name desync**: profile runner registered builders under
   `OpenRouterModelNames.openRouter` while the suite binds actors via
   `DefaultModelNames.appleFoundation` → resolution threw before any call.
   Builders now registered under both keys.

3. **Upstream constraint**: free-tier models rate-limit under burst retries
   (`http_error`, raw 429 on `laguna-xs-2.1:free`). Next step: add 429
   backoff/retry to the OpenRouter client, then rerun edit_01 ops-vs-baseline
   with attribution.


## AFM ops-arm close reading (edit_01, 2026-08)

AFM is unblocked and the full loop runs (27 decisions, real list_dir/read/
patch_file traffic). Transcript analysis:

- Alternating infers arrive with `tools=[none]` / Swift
  `tools prepared=0/0 requested`; on those turns the model emits guessed
  calls like `patch_file({})` because it only ever saw tool NAMES echoed in
  result-feedback text.
- Suspect located: `DefaultGenerationHandler` streaming branch —
  `model_router.dart` sends `'tools': null` there
  (`AppleFoundationNativeClient implements StructuredTextStreaming`),
  while the blocking branch forwards `toolRegistry`. Suite actors have
  `ActorTools('default')` and projection copies it correctly; the drop is
  in this handler/router divergence, not in projection.
- Next step: route text+tools requests through the blocking infer path (or
  attach registry to the streaming request), rerun edit_01 ops arm, expect
  `patch_file{path,anchor,new_text}` with real args — then the 59%-cut
  measurement becomes valid against AFM.
