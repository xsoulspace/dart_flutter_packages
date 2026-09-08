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

---

## STATUS (2026-09-07, post ADR 0033/0034 — pre re-run)

- Graduation LANDED and gate-proven: program replaced locate/zoom/impact;
  the ONE edit verb absorbed edit_section/edit_key (creation included);
  the one-truth surface measures **1,424 chars/4 → cutBudget 628,
  fits=true** (was 2,268 → 36 at the 2026-09-06 run).
- The on-device smoke (task_grammar, attempts 1) PROVED `end_after_tool`
  (generations end on the first tool result, `ended_by:one_move`) and
  found+fixed a FATAL bridge double-resume; dylib rebuilt, bridge suite
  17/17.
- The full re-run (all four rows) is PENDING — the 2026-09-07 attempt was
  SIGKILLed by concurrent-build contention on this machine. Run on a
  quiet machine: `dart run bin/afm_wave_gate.dart` (expect: derivation
  row per run; `decision_dropped` never `backend_failed` retry loops;
  no `tool_round entries` growth past one round).

---

## P1-FIX RE-RUN (2026-09-08, the named-bounce loop engaged — driver + surface drift fixed first)

Driver state: rows 3/4 re-pointed to the unified verb (the old prompts
still taught `edit_section`/`edit_key` — dead after ADR 0034); ALL
teaching surfaces converged to the read program (the `task_grammar`
suffix + ~20 model-facing bounce strings still taught
`meaning_zoom`/`meaning_locate`/`meaning_impact` — tools removed from
the profile by the ADR 0030 §3 graduation; the tiny model OBEYED the
stale teaching and burned rounds on ghost verbs — fixed and grep-gated
in `--dry`); read bounces now carry mechanical repair data (top-5
candidate ids on unknown focusId AND on no-match locate; the cursor-law
hint: "omit focusId — the last locate's top hit feeds zoom/impact/read"). Logs: `afm_wave_*_run1.log` (2026-09-08 entries).

| row | verdict | decisions | tokens | wall | failure class |
|---|---|---|---|---|---|
| task_grammar | **PASS** 1/1 (3rd consecutive) | **1** | **2,073** | 21 s | — |
| trusted_author | **FAIL** (5th published) | 30 | 63,633 | 845 s | final gate: dart test exit=1 — read-side query-composition class |
| md | **FAIL** (2nd published) | ~3 | ~8k | 70 s | the model STOPPED EARLY: one pre-scan locate (tree_empty bounce), a scan, then no further moves — never reached the edit |
| yaml | **FAIL** (1st published) | 3 | 6,176 | 131 s | 2 tool rounds, near-immediate give-up — same early-stop class |

### What the P1 fix proved (rows publish, classes named)

1. **The opaque ToolCallError class is GONE.** Every failed call now
   reaches Dart as named bounce data; verdicts publish; no 59–109-gen
   verdict-less loops. The P1 fix holds.
2. **Consent + permission surfaces work on-device** (`plan-allowed
   pack_write: dart/author_area (1/2)` in every trusted run) — the
   trusted-author MACHINERY is proven; the model's path to it is not.
3. **Row 1 is the amortization endpoint, reproducibly**: 1 decision /
   1 round / ~2k tokens whenever the surface teaching is honest; it
   broke (3–31 decisions) exactly when stale teaching leaked — the
   strongest small-surface-sensitivity evidence yet.

### The measured no-recovery verdict (ADR 0034's graduation question)

FINAL (2026-09-08, all four rows measured): **the 4k AFM tier does not
reliably compose the multi-step read→edit flow on the unified surface.**
Row 1 (the single READY move) passes reproducibly at 1 decision; every
multi-step row fails, each in a NAMED class: invented queries/focusIds
(trusted — 5 runs), early-stop before any edit (md, yaml). The bounce
ladder teaches mechanically (all classes named, hints carry real node
ids incl. the fs tier after the kind-filter fix) — teaching fires but
does not converge within the tier's budget. Per ADR 0034's own
criterion the surface must adapt for this tier; the named repairs
(decision needed, NOT built):

- **(a) host pre-pass for consented packs AND multi-step rows** — the
  pack names the symbol; the host resolves the id mechanically (row 1's
  proven pre-pass path) and emits the READY decision. The model's only
  job: carry the move; consent stays host-side. The row then measures
  CONSENT (its stated purpose), not id-resolution. Generalizes: any
  row whose steps are mechanically resolvable gets a ready-decision
  pre-pass; the multi-step tier is the LARGER model's surface (J8 rung
  2 escalation) — that split is now measured, not assumed.
- **(b) tier escalation for multi-step rows** — the overseer swap path
  (J8 rung 2) promotes the row to a larger model when the bounce ladder
  exhausts.

### New named driver defects (harness backlog)

- **Exhausted-attempt pump**: after the goal-attempt budget exhausts,
  the react-continuation pump re-sends the identical "attempt N/3"
  prompt (measured Σ26, ~2 min wall, ~10k tokens) instead of ending
  the decision. The decision must END on exhaustion (J8 rung 1).
- **Scoped-check vs outer-gate anomaly** (one observation): an edit
  landed with the in-materializer check exit 0 (520 ms — warm kernel)
  while the outer `dart test` gate failed (3,719 ms). Same command,
  same jail — needs a controlled LLM-free reproduction before any
  code change.

---

## P0 RE-RUN (2026-09-07, the converged surface — ADR 0033/0034)

Driver state: dylib rebuilt (crash fix in), one-truth profile 1,424 →
cutBudget 625 fits=true, `end_after_tool` live. Logs:
`afm_wave_rerun_*.log`.

| row | verdict | decisions | tokens | wall | failure class |
|---|---|---|---|---|---|
| task_grammar | **PASS** 1/1 | **1** | **2,024** | 24.5 s | — |
| trusted_author | killed @900 s | gen=109 | — | — | opaque-ToolCallError loop (18) + model flailing (wrong-class actions, malformed programs, refresh loops) |
| md | FAIL (published) | 15 | 30,144 | 237 s | final gate: the edit NEVER landed — 1 wrong-class action (bounced) + 8 opaque ToolCallErrors |
| yaml | killed @820 s | gen=59 | — | — | opaque-ToolCallError loop (10): garbage slots (`executableId:"null"`, body=Dart prose), same-cut retries |

### Row 1 proves the wave's structural claims end-to-end

1 decision / 1 tool round / 2,024 tokens (was 2,864 at 49.5 s → 24.5 s):
the ready move executed via `edit_symbol.apply_executable`, the patch
landed (analyze_exit 0, check_exit 0), and the generation ENDED on the
first tool result — `end_after_tool` proven on-device (immediate `done`,
no `decision_final` trace, transcript held at 3 entries). The
amortization endpoint now runs at HALF the tokens of the 2026-09-06 row.

### The systemic finding: opaque schema-invalid calls bypass the named-bounce architecture

All three failing rows died in ONE new class: **the model's tool call
fails the framework's GenerationSchema validation → `ToolCallError` →
generic `generation_error` → same-cut retry.** The call NEVER reaches
Dart — so the one-move bounce, the class-teaching hints (ADR 0034), and
the whole repair-hint contract never fire; the ladder is blind (the
error is not window-class, so it retries; the retry recomposes the same
confusing cut). Measured: 18/8/10 ToolCallErrors per failing row, loops
of 59–109 generations — and the J1.5 budgets (maxToolRounds × attempts)
did NOT contain the class (a failed generation is not a tool ROUND).

The trigger is concrete: a 2–4k model facing the 10-action union enum +
8 slots omits required slots or invents values (`executableId:"null"`,
Dart prose in `body`). ADR 0034's per-class bounce teaching is the right
shape but requires the call to LAND.

### The fix (next P1 — named, not built)

1. The bridge catches `ToolCallError` and surfaces a NAMED code
   (`tool_args_invalid`) carrying the failing tool + the framework's
   detail — never a bare `generation_error`.
2. The harness treats it as bounce-class DATA: a named beat on the
   actor's thread ("args failed validation for <tool>; required slots:
   …"), no same-cut retry burn.
3. The named-bounce loop (ADR 0034) then engages — and the row re-runs:
   does the tiny model RECOVER through class-teaching bounces? That is
   the graduation measurement for the union enum itself. If it does not
   recover, the enum splits per class (a measured surface change, ADR).
