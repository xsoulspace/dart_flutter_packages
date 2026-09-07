# ADR 0033 — The derived context equation: one truth, mechanical repair, decision ends after the move

- Status: Accepted (2026-09-07)
- North Star impact: `amends` (0028 §3's re-admission policy narrows from
  "relevance-ranked beats" to a bounded last-result set; the amendment is
  recorded HERE, before code) + `clarifies` (applies the context-ownership
  law 0018/D7 as ONE derived equation; applies 0028's one-move contract
  MECHANICALLY instead of by prompt hint).
- Builds on: [0018](0018_meaning_view_zoom_projection_context_ownership.md),
  [0020](0020_cut_composition_api.md),
  [0028](0028_one_move_per_decision_native_loop_bounded.md),
  [0030](0030_one_decision_one_program_surface_convergence.md)
- Measured trigger: the AFM wave gate (2026-09-06,
  `benchmark/runs/afm_wave_results.md` + the 2026-09-07 correction
  addendum). Retrospective verification of the first failure analysis
  found: the wave rows failed on PER-DECISION arithmetic (fixed overhead
  2,268 chars/4 ≈ 3.3k native vs the 4,096 window), NOT cross-decision
  accumulation; the one-move contract held (7 decisions / 7 rounds / 1
  move each); the overhead gate measured a hand-built 6-tool registry
  while the runner registered 9 verbs; and the failure loop burned the
  attempt budget on ~20 futile same-cut retries.

## Context

Three seams were never closed into mechanisms:

1. **The numbers were never one equation.** `ProjectionBudget` (constant
   4,000, ~10 call sites), the client pre-flight `maxContextTokens`
   (3,800), the native window (4,096, measured R9.1), the output reserve
   (1,024, finding 18), and the chars/4 → native undercount (~45%,
   ADR 0028 §Context.3) live in four layers with no derivation. The
   consequence is arithmetic, not accumulation: the 9-verb meaning
   profile's fixed overhead alone, at native truth, exceeds the window
   before any cut content — every multi-round AFM row is doomed by
   construction, and no composition change can save it.
2. **The overhead gate measured a different registry than the actor
   sees.** `meaning_profile_overhead_test.dart` claimed "one truth, not
   a rebuilt list" but hand-registered 6 tools while
   `runCodingAgentOnce` registers 9 (`meaning_locate`, `edit_md`,
   `edit_key` invisible to the gate). The surface grew with every gate
   green.
3. **Repair was a prompt, not a mechanism.** On ANY backend failure the
   response processor re-inserts an `OpenDecision` whose prompt is the
   fixed string "Error: backend_failed. Retry with tighter context." —
   and nothing shrinks the cut on retry. On a hard window overflow the
   retry is futile BY CONSTRUCTION; the wave md row burned its attempt
   budget ~20× this way. Related: the one-move contract bounce
   (ADR 0028 §2) is *returned as a string to the native loop* — it
   bounds EXECUTION, not the native window; the model may keep calling
   tools, each bounce appending to the native transcript, because
   "the model ends its turn" is a hint the model can ignore. A tiny
   model must never be trusted with a law.

## Decision

1. **The derived context equation (closes D7 into one formula).**
   `cutBudget = window(native, measured) − ceil(overhead(live registry,
   chars/4) × nativeTruthFactor) − outputReserve − margin`, with
   `nativeTruthFactor = 1.45` (ADR 0028, measured), `window = 4,096`
   (`model.contextSize`), `outputReserve = 1,024` (finding 18),
   `margin = 10%` of the remainder. The runner DERIVES the
   [ProjectionBudget] from the LIVE registry (never a constant) and the
   derivation row (every term) is printed with the run. If the derived
   budget cannot fund a minimal cut, that is a NAMED condition — the
   profile does not fit the tier; the repair is ADR 0030 surface
   convergence (the profile must SHRINK), never trimming and never a
   bigger constant.
2. **The overhead gate meters ONE truth.** The meaning-profile tool
   surface is built by ONE exported function
   (`buildMeaningProfileSurface`), called by the runner AND the gate.
   The gate binds to the one-truth measurement with a narrow published
   range: any verb added, removed, or reworded breaks the row and
   forces re-publication. "One truth" is a function, not a comment.
3. **Mechanical repair ladder — no same-cut retry on window-class
   failures.** Backend failure codes are threaded to the response
   processor (the router no longer swallows them into `null`). A
   `context_window_exceeded` (or any window-class) failure DROPS the
   decision: no retry `OpenDecision`, a named
   `decision_dropped: context_window_exceeded` outcome beat on the
   actor's thread, attempt budget unburned for the futile round. Repair
   routes to the host ladder (converged profile / ready-move
   one-decision tier / escalate) — never back into the same cut.
4. **The decision ends mechanically after the move.** The native inline
   loop gains a request flag (`end_after_tool`): when set, the Swift
   side, on delivering the FIRST tool result, finishes the generation
   with that result instead of resuming the model. The executed move
   still lands through the world (ToolCallEvent → tool result beat);
   the next decision is a fresh cut. This replaces ADR 0028's
   repair-hint hope with a mechanism: the native transcript can no
   longer grow past one round. Flag-gated per request; default OFF
   everywhere until the on-device wave row re-runs, then it becomes the
   meaning profile's default (and later, by the same gate, every model
   decision's).
5. **Step-driven composition amends 0028 §3 (decided; build pulled by
   the next failing row).** The cut's observations slot narrows from
   "relevance-ranked history" to: the plan step's target, the cursor,
   the LAST tool result, and mechanical verdicts — nothing else. The
   unanswered prerequisite is named: for tasks the task grammar cannot
   parse, the host must still compose the plan — the task-grammar
   pre-pass (ready-move leading frame) generalizes into the mechanical
   planner rung; until that lands, the observations slot keeps its
   current capacity as the measured, honest fallback.

## Consequences

- `deriveProjectionBudgetTokens` + `buildMeaningProfileSurface` land in
  the host; the runner consumes both; the overhead gate meters the
  builder and publishes the derivation row (current truth: the 9-verb
  profile does NOT fit the AFM window — the row is the evidence that
  ADR 0030 graduation is the required next step, not a tuning target).
- Window-class failures stop consuming attempt budgets; the wave
  failure class changes from `backend_failed` retry loops to a single
  named `decision_dropped` row.
- The Swift bridge grows the `end_after_tool` flag (native-tier work:
  raw Swift edit is a declared escape, surface_gaps ledger); the
  on-device re-run of the wave rows is the graduation measurement.
- Named, not built: the mechanical planner rung for unparseable tasks;
  the step-driven composer implementation; converged-profile graduation
  (ADR 0030 §3 gates it on the measured row).
