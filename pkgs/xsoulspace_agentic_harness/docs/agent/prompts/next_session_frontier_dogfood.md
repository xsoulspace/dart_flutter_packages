# Next session — frontier resolvers + dogfood debt (handoff brief)

> The one-page brief for the session that lands repair (a)/(b) and closes
> the dogfood debt. All decisions are already measured and recorded — this
> session EXECUTES, it does not re-litigate.

## Read first (in order)

1. `pkgs/xsoulspace_agentic_harness/benchmark/runs/afm_wave_results.md` —
   § DECIDED (the (a)/(b) measurement: 0% of failed steps needed model
   composition, 100% mechanically resolvable) + § P1-FIX RE-RUN.
2. `docs/decisions/0009_…md` — **the 2026-09-08 Amendment**: StepAction is
   the mechanical slot; resolvers live IN the frontier; NO parallel
   pre-pass; the task-grammar pre-pass fork gets RETIRED into the frontier.
3. `docs/decisions/0035_…md` §5 — the hard surface laws (zero-arg-delta,
   dart action names verbatim, no format literals in bounce strings).
4. `pkgs/xsoulspace_agentic_harness/docs/agent/PLAN.md` — the P1 rows
   (pump fix + resolvers-into-frontier), P2 rows (tier routing, wave-log
   analyzer, xml binding P3), the per-language gate matrix (ts/cs landed,
   R7e rows open).
5. `pkgs/xsoulspace_agentic_harness/docs/agent/surface_gaps.md` — the
   ledgered dogfood debt (the two 2026-09-08 rows).

## Work order

1. **Pump fix (P1 prerequisite)**: after the goal-attempt budget exhausts,
   the react-continuation pump re-sends the identical "attempt N/3" prompt
   (measured Σ26, ~2 min wall, ~10k tokens) instead of ending the decision.
   The decision must END on exhaustion (J8.1). Gate: a scripted LLM-free
   test asserting exactly ONE re-send, then end.
2. **Resolvers INTO the frontier (repair (a))**: `StepAction` steps resolve
   mechanically (pack executables name the symbol; grammar verbs;
   prompt-named file+anchor/keypath) and the ready decision delivers via
   `openFreshDecision` — the actor CARRIES moves, never composes ids.
   Retire the task-grammar pre-pass fork INTO the frontier (one mechanism).
   Zero-token mechanical actors may work consented ready steps while the
   model actor works. Ambiguity bounces with candidates (locate-hints
   law) — resolution is TOTAL or it bounces.
3. **Tier routing as a frontier property (repair (b))** — NAMED-NOT-BUILT
   unless the trigger fires: a step no resolver can resolve projects as
   tier-routed; build only on the first real unresolvable task
   (three-failures rule). Do not build speculatively.
4. **Dogfood debt** (the point of the session — the harness must be
   convenient enough that agents never reach for bash):
   a. The pi extension exposes ONE read tool — `harness_meaning_program
      {ops:[…]}` — replacing the legacy `harness_locate`/`harness_zoom`
      wrappers (they currently delegate to the mover: ~140 s + refusal —
      measured in-session). The mechanical-read classifier asserts against
      the LIVE registry, not a name list.
   b. `wave_log_classify` — a mechanical directive over
      `benchmark/runs/*.log` producing the per-run
      mechanically-resolvable-vs-composition-required split (never agent
      bash/python again).
   c. Then DOGFOOD: run the wave rows 2–4 re-run through the surface; the
      session's own edits (md sections, Dart member bodies) go through
      `harness_edit`; record the A/B row in `results_seam_speed.md`.

## Gates

- Pump: scripted test, exactly-one-re-send.
- (a): wave rows 2–4 re-run on-device → pass@1 each at 1–2 decisions
  (the graduation measurement for the repair); the pre-pass fork retired.
- Dogfood: reads mechanical (<100 ms); one real edit through `harness_edit`
  with the A/B row; gap rows closed in surface_gaps.md.

## Laws that still bind

The model never writes code tokens, never sees an AST, never holds the
tree (Agent = G ∘ F); one edit verb, zero-arg-delta; new file classes =
bindings, never loops; budgets monotonic; every test ends `expectIdle`;
failures publish as named data; the coding agent IS the coding agent —
its own packages are its backlog.
