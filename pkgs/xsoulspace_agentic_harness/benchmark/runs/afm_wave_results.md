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
