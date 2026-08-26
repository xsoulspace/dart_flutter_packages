# Phase 4 Results — 20-task coding suite

Date: 2026-08-25. Fixed task set: 20 tasks across 5 classes (`edit` 6,
`search` 4, `chain` 3, `refactor` 4, `bugfix` 3) with deterministic
pass/fail checkers. Raw JSONL traces + markdown reports:
[`benchmark/coding_suite/runs/`](../../../../lib/src/benchmark/coding_suite/runs/)
(`afm_run.jsonl`, `openrouter_run.jsonl`, per-run `.md`, full logs).

## Runs

| Backend | Label | Pass rate | Wall clock | Notes |
| --- | --- | --- | --- | --- |
| Apple Foundation Models (on-device) | `afm` / `apple-foundation` | **5/20 (25%)** | 2416 s (~40 min) | `bin/coding_suite_afm.dart`, guided-decision structured handler |
| OpenRouter hosted | `openrouter` / `dots-studio/dots-3-note-preview:free` | **4/20 (20%)** | 2667 s (~44 min) | `bin/coding_suite_openrouter.dart`, native tool calling |

**Headline claim status:** the tiny-model harness pass rate is low (25%).
Reported plainly — this is the claim-defining number and it does not yet
support an efficiency-at-parity claim.

### ⚠️ Comparison-column caveat

The planned third column (pi driving this harness via ACP/MCP) could not be
produced: no ACP/MCP server implementation of the harness exists. Per ADR
0007 §4 this is logged in
[`docs/decisions/extensibility_ledger.md`](../../../../docs/decisions/extensibility_ledger.md)
as *"pi-driving-harness-via-ACP has no server implementation; gap recorded,
not built inside Phase 4."*

Therefore the OpenRouter column is labeled **harness+hosted**, NOT
pi-vs-harness. Both columns measure *this harness* with different backends;
neither measures pi.

## Per task class

| Class | AFM pass | AFM tokens/task† | OR pass | OR tokens/task† |
| --- | --- | --- | --- | --- |
| file_edit | 4/6 | 626 | 3/6 | 575 |
| search_then_edit | 1/4 | 700 | 0/4 | 694 |
| tool_chain | 0/3 | 610 | 1/3 | 532 |
| multi_file_refactor | 0/4 | 811 | 0/4 | 742 |
| bug_fix_with_test | 0/3 | 587 | 0/3 | 597 |

† **Token accounting caveat:** these are harness-side projections from each
actor's `Situation.tokensUsed`. AFM exposes no usage numbers from the native
bridge; OpenRouter usage is also projected through the same path for
comparability. Treat tokens/task as harness-side projection accounting, not
provider billing figures.

## Operational metrics

| Metric | AFM | OpenRouter |
| --- | --- | --- |
| LLM calls/task (avg) | 21.5 | 18.8 |
| Tool calls/task (avg) | 20.9 | 18.2 |
| Escalation rate | **0** (structurally: single-tier backend, no higher tier exists to escalate to — recorded explicitly, not assumed) | **0** (same) |
| Transient errors | 0 | 0 |
| Timeouts | 0 | 0 |

## Failure modes

Traces carry a deterministic `failure_mode` classifier (timeout / no-llm /
transient-errors / tool-error / wrong-edit). Raw counts of failed tasks:

- AFM: 15 × `tool-error`
- OpenRouter: 16 × `tool-error`

**Known coarseness, stated rather than massaged:** the classifier labels a
failure `tool-error` if *any* tool call in the run returned an error result.
Normal agentic exploration (e.g. `read` on a file the agent has not written
yet) produces such errors, so almost every failed run trips it. The checker
details in the traces show the underlying reality is overwhelmingly
**wrong-edit**: required content missing, forbidden content still present, or
output files never written. No silent retries were added; `--retries 2`
(default) checker-feedback retries applied uniformly on both backends.

Failure examples (full detail in traces):
- Multi-file refactors fail on both backends (0/4 each): agents edit one file
  but miss the rename/extraction in the others.
- `bugfix_03_write_failing_test_pass`: neither backend ever wrote the required
  test file.
- AFM's passes concentrate in single-file edits (4/6); anything requiring
  multi-step synthesis (chains, refactors, bugfix+test) is 0–1 passes.

## Honesty notes

- No retries beyond the default `--retries 2`; no failures reclassified or
  rerun.
- AFM `GenerationError -1` transient framework flakiness did not occur in
  this run (`transient_errors = 0` everywhere); it remains auto-counted in
  traces if it recurs.
- The Swift regression gate was green pre-run (17/17); bridge sources
  unchanged during the run.

## Next

- The ACP/MCP server gap is the blocker for the real pi-vs-harness column
  (ledger entry above).
- Phase 6 snapshot/restore per ADR 0007 §5 (`ecsly_serializable` +
  `universal_storage`; golden oracle = post-restore projections match
  pre-snapshot modulo canonical normalization).
