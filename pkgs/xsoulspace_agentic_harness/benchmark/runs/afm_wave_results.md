# AFM wave gate — first on-device run (2026-09-06, macOS, real apple_foundation_afm)

Driver: `xsoulspace_inference_apple_foundation/bin/afm_wave_gate.dart`
(in-process R7e pattern; fresh jail per run; tokens = Situation.tokensUsed,
projection). Pass@1 attempt budget noted per row. Logs:
`benchmark/runs/afm_wave_<row>_run1.log` (+ summary).

| row | verdict | n | decisions | tool_rounds | tokens | wall | failure class |
|---|---|---|---|---|---|---|---|
| task_grammar | **PASS** | 1 | **1** | 1 | 2,864 | 49.5 s | — |
| trusted_author | FAIL | 1 | 5 | 5 | 13,910 | 207 s | context overflow loop (`backend_failed: retry with tighter context`) |
| md | FAIL | 1 | 7 | 7 | 21,821 | 363 s | same |
| yaml | FAIL | 1 | 7 | 7 | 22,326 | 403 s | same |

## The headline: task-grammar tier is REAL-MODEL PROVEN

After one surface-teaching fix (below), the on-device AFM model executed the
host pre-pass's ready move in **exactly 1 decision / 1 tool round / 2,864
tokens** — pass@1 1/1, zero composed tokens (ids from the pre-pass, chain
from the pack). The decision-amortization endpoint is real on a 2–4k model.

## The dogfood loop (3 fixes landed DURING the runs — the runs that failed are the data)

1. **Ready move must LEAD** (task_grammar): the pre-pass directive was
   trailing prose — the model explored (scan→zoom) and never executed it.
   Fix: the goal frame now LEADS with an imperative READY MOVE (forbids
   scan/explore). Result: 23,987 tokens/7 decisions FAIL → 2,864/1 PASS.
2. **`repo_etl scan` is now an IDEMPOTENT ENSURE** (workspace): a small
   model's natural first move is scan; bouncing it as an error on a built
   tree looped the real model 4×. Scan on a built tree now runs the same
   mechanical reconcile and returns ok:true `already_built`.
3. **`edit_section`/`edit_key` registered on the daemon meaning profile**
   (they existed but were never registered — the rows were unrunnable).

## The systemic finding: the profile outgrew the AFM window

Fixed overhead measured **2,268 tokens** (was 1,408 at R7e — meaning_locate
+ edit_md + edit_key registered since), leaving ~1,732 of the 4k AFM window
for cut+transcript. Every multi-round row overflowed at round 2–3 into
`backend_failed` retry loops that consumed the attempt budget. Description
trims (−~380) do NOT close the gap. **ADR 0030's converged profile (program
replaces zoom+impact) is now EVIDENCE-BACKED as the required next step** for
all multi-round tiny-model work; until then only one-decision rows (the
task-grammar path — the amortization endpoint) fit the window.

## Rows for the record

- task_grammar: **pass@1 1/1, 1 decision** — R7e-class row for the P2
  decision-amortization tier.
- trusted_author: FAIL — overflow class. Consent path itself worked
  (`plan-allowed pack_write … — diff: 3 lines` audited in-run).
- md / yaml: FAIL — overflow class; materializers remain LLM-free-gated
  (their real-model rows re-run after ADR 0030 graduation).

---

## CORRECTION (2026-09-07 retrospective — ADR 0033)

The first post-mortem of these rows ("the conversation came back through
the native bridge and a recency replay") was materially wrong:

1. **No cross-decision resume occurred in these runs.** The `resumed=true
   … entries=…` evidence cited is from the Aug 28 intent-closure logs —
   the PRE-0028 era. The wave logs show the one-move contract HOLDING:
   `decisions: 7, tool rounds: 7, moves: {repo_etl.scan: 7}` — one call
   per decision, fresh cut per decision.
2. **The binding failure was per-decision arithmetic, not accumulation.**
   Fixed overhead 2,268 chars/4 ≈ 3.3k native (×1.45, ADR 0028 §Context.3)
   + 1,024 output reserve vs the 4,096 window → no room for a cut BEFORE
   any content. No composition change could have saved rows 2–4.
3. **"Retry with tighter context" is harness-authored** (a fixed prompt
   stamped onto any failure, generation_systems) — the backend never
   "managed context by shrinking a conversation". Nothing shrank on
   retry; the loop burned ~20 futile rounds per row.

### What landed (ADR 0033)

- **Derived context equation** (`derived_context.dart`): the runner
  derives the cut budget from the LIVE registry — window(native, 4,096,
  measured) − native-truth overhead (×1.45) − output reserve (1,024) −
  margin, with a named min-cut floor (600). The wave row now prints the
  derivation; the current profile honestly derives `cutBudget≈36,
  fits=false`.
- **One-truth overhead gate**: `buildMeaningProfileSurface` is the ONE
  builder for the runner AND `meaning_profile_overhead_test.dart` (the
  gate previously hand-built 6 of the runner's 9 verbs). Measured
  one-truth: 2,078 chars/4 lean (8 verbs; +write_review ≈ 2,268).
- **Mechanical repair ladder**: window-class failures (`context_window_exceeded`)
  DROP the decision with a named `decision_dropped` beat — no same-cut
  retry, attempts unburned. Failure codes are threaded from the router
  (previously swallowed into null).
- **Mechanical one-move end**: `end_after_tool` flag — the Swift bridge
  finishes the generation on the FIRST tool result instead of resuming
  the model (bridge/tests green; on-device wave re-run pending).

### Re-run route

Rows 2–4 re-run AFTER ADR 0030 graduation (program replaces
locate/zoom/impact schemas — the profile must SHRINK below the derived
floor). Until then the only expected-viable rows are one-decision
(ready-move) rows.
