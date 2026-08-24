# Agent Harness — Plan

> Goal: prove + harden the tiny-context (2–4k) cinematic multi-actor harness.
> Thesis: harness = intelligence amplifier; model = replaceable reasoning
> primitive. History and landed work: [history.md](history.md). Durable
> decisions: [ADR Index](../../../../docs/decisions/README.md).

The working model is a living, multi-linear game world. Memory was removed as
a primitive; now planning is too (ADR 0009). What remains ahead, in order:

---

## Ahead — ordered

### A1. Fair comparison baseline — **landed 2026-08**

The Phase 4 columns were not comparable (three verified confounds — see
[plan_fair_pi_comparison.md](plan_fair_pi_comparison.md)):

- **C1**: OpenRouter client flattens context into one user message (no real
  chat-completions shape, no real usage accounting).
- **C2**: AFM and OR ran different decision machinery (guided schema vs native
  tools).
- **C3**: No pi column — resolved by driving pi via its **SDK**
  (`createAgentSession()`), not an ACP server we never built.

Steps: C1 fix + A/B → decision-path unification pilot → tool-parity decision →
pi SDK driver → run matrix (`harness+AFM` / `harness+OR` / `pi+OR`, same model)
→ publish `results_comparison.md`.

**Result:** C2 confirmed as the dominant confound. Guided-schema arm scored
0/20 (2 tool calls total); native-tool-calling arm scored 6/20 (262 tool
calls). Same model. pi scored 19/20 on the native loop. The remaining
harness-vs-pi gap is edit quality, not decision machinery — the model can
act but writes wrong content. See
[results_comparison.md](../../benchmark/docs/agent/results_comparison.md).

**Implication for tiny models:** guided schema is a bottleneck, not an
amplifier, at this scale. Native tool calling should be the default decision
path; guided schema remains available via `--decision guided` for targeted
A/B. The harness thesis ("harness = intelligence amplifier") now has a clean
mechanism to test: A2 plan-frontier + decomposition should close the edit-
quality gap without changing the model.

### A2. Goals as vectors, plans as projections (ADR 0009) — *falsification passed; productionize*

**Status update (2026-08):** the falsifying experiment ran across all 20
suite tasks — **−39% LLM calls, −24% tokens/task, equal 20/20 pass rate**
([results](results_plan_falsification.md)). Not noise. Remaining work to
production shape, in order:

1. **Purity** — **landed 2026-08**: move the frontier policy off direct fs reads — predicates run
   as verifier tools behind seam 3, results become beats, policy stays pure
   (conformance suite in A4 applies).
2. `Goal` entity: direction + tool-callable success criteria + lifecycle;
   predicate tools enter via seam 3 (`run_tests`, `diff_check`, `ast_check`).
3. Step entities on a verifiability spectrum (`mechanical | observable |
   open`) with status machine and evidence-beat links; superseded steps stay
   queryable.
4. `OpenDecision.stepId` backlink → agency grants carry acceptance criteria
   in-frame.
5. Plan-frontier projection: explicit `goalLink`/`dependsOn` traversal,
   token-budgeted, green-screen elsewhere.
6. Real-model probe: **ran twice** — see
   [results_plan_falsification.md](results_plan_falsification.md)
   (§real-model, §follow-up). Cumulative token accounting landed (real spend
   ~20× the old metric — prior published numbers are undercounts). Role
   prefixes exonerated by A/B. Root cause of baseline thrash identified:
   pre-existing fs-jail path rejections (present 156× in the Phase 4 log),
   masked then by the checker-retry loop. **Mitigations landed + re-probed:
   −36% calls, −50% cumulative tokens on real AFM; edit_05 passes with 1 call
   (baseline: 17, fail).** **Idle-coverage rule LANDED** (mechanical
   "idle + open goal ⇒ verify", bounded to 1 nudge — results §round 4) and
   **decomposition mechanics LANDED** (per-step criteria in-frame, zero
   close-out: scripted refactor tasks −44…−72% cumulative tokens at equal
   pass rate — `benchmark/decomposition_experiment.dart`). Next lever:
   real-model decomposition probe (decompose call via guided schema), then
   the Phase 4 matrix re-run under cumulative token accounting.
7. Decomposition as one agentic act per goal (amortized; escalation tier OK),
   fidelity measured via ADR 0004 causal coupling.

New metrics: mechanical-step share (work completed without any LLM call —
already measured at 100% for verification in the falsification run),
escalation rate per task class, decomposition fidelity via ADR 0004 causal
coupling.

### A3. Reduction fidelity / structurification (Phase 4b)

Unchanged in substance, scope narrowed: keyword-drift recall now measures
*execution-context* quality for steps (plan discovery uses explicit links and
is drift-free by construction). Reduced beats must still trigger correct rays
and causally gate scripted success.

### A4. Seam conformance suites (Phase 5b)

Per ADR 0007 §2: policy determinism + purity canary; tool timeout/error-shape/
serialization round-trip; handler fault matrix; projection budget assertion in
debug mode. Verifier-tool conformance joins this list when A2 lands.

### A5. Snapshot/restore + baseline table (Phase 6)

Real deliverable, not the REPL prototype: persist beats/threads/**goals/
steps** via `ecsly_serializable` + `universal_storage`; rebuild facet index
from restored beats (derived state never source-of-truth); crash mid-decision
restores to a re-opened decision; golden oracle — post-restore projections
byte-match pre-snapshot cuts. Then publish the final comparison table from A1
as the headline artifact.

### A6. Everyday CLI host (thin)

REPL on `HarnessLoop.start()`: streaming deltas, input-as-decisions while
idle, cancel-in-flight = task cancellation + agency release, `/situation`
inspector, snapshot autosave, confirmation-gated tools. Anything beyond that
is an extensibility-ledger entry, not core.

---

## Standing rules

- Every published benchmark column states backend, decision path, tokens
  source, and tool surface. Failures remain data.
- Escalation-rate metric ships next to every pass-rate table — quiet
  escalation means the tiny-model claim is failing silently.
- Extensibility ledger: three host entries against the same seam trigger a
  design conversation.
- Gravity check before structural work: (a) tiny model stays useful,
  (b) fewer LLM calls, (c) context bounded + derived, (d) LLM-free testable.
- Scope tripwires for A2 specifically: no replanning policy engine, no plan
  schema versioning, no planner agent. Steps in, projection out, checks fail
  loudly.
