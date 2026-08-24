# ADR 0009 Falsification Results — plan-frontier vs ReAct close-out

Date: 2026-08. Experiment:
[`benchmark/plan_falsification_experiment.dart`](../../../benchmark/plan_falsification_experiment.dart).
Run: `dart run benchmark/plan_falsification_experiment.dart`

## Design

ADR 0009's falsifying experiment, verbatim: express coding-suite steps with
checker-based success criteria, run the loop where mechanical steps skip the
LLM entirely, measure tokens/task delta.

- **Both arms**: identical fixtures, identical stateful scripted model
  behavior (`OneActionPerCallHandler` — one action per call, mirroring real
  multi-round model behavior), identical deterministic checkers,
  Goal + step entities present in both. **The only variable is the decision
  flow**: default `ReActContinuationPolicy` (continuation after every tool
  result; one extra call to say "done") vs `PlanFrontierPolicy`
  (goal success criteria evaluated mechanically when a tool result lands;
  verified goal ⇒ no continuation ⇒ loop idles).
- All 20 suite tasks, scripted backends, no real model — measures harness
  mechanics, not model capability.
- Known deviation from production shape: the frontier policy reads the jail
  fs directly instead of consuming verifier-tool beats (purity gap documented
  in the experiment header; the real design keeps policies pure via predicate
  tools behind seam 3).

## Results

| Metric | Baseline (ReAct) | Plan frontier | Δ |
| --- | --- | --- | --- |
| LLM calls (20 tasks) | 51 | 31 | **−39%** |
| Tokens (20 tasks) | 8,645 | 6,572 | **−24%** |
| Tokens/task avg | ~432 | ~329 | **−24%** |
| Pass rate | 20/20 | 20/20 | equal |

Per-task pattern is uniform: baseline pays `actions + 1` calls (the +1 is a
pure narrative close-out), plan-driven pays exactly `actions`. Token delta per
task −20…−28%, growing slightly with fewer actions (close-out overhead is
fixed-cost dominated).

**Mechanical verifications: every checker evaluation in the plan arm (31
total) ran with zero LLM involvement.** Mechanical-step share for verification
work: 100%.

## Methodology note

An earlier draft used the stateless `ScriptedSuiteHandler` for the baseline;
it re-emits all steps on every continuation round until `maxToolRounds`
exhausts (17 "calls" for a one-write task). That measured the handler, not
the harness — replaced with the stateful handler so both arms share identical
model behavior.

## Verdict

**Not noise. The ADR 0009 mechanism survives its own falsification attempt.**
The close-out call elimination alone buys ~24% tokens/task at zero pass-rate
cost before any real decomposition, projection-budget tuning, or retry-loop
tightening — those stack on top.

## What this does NOT yet prove

- Real-model behavior: local models may waste the saved close-out call
  elsewhere (e.g., failed criteria loops). Next probe: same A/B against AFM on
  the 6 edit tasks.
- Decomposition quality: steps here were hand-authored. The decompose-once
  transform and its fidelity (ADR 0004 causal coupling) are unmeasured.
- Purity: frontier policy must move to verifier-tool beats before this is the
  production shape.

---

## Real-model probe (AFM, 6 edit tasks) — 2026-08, indicative

Script: `apple_foundation/bin/coding_suite_plan_probe.dart` (both arms, same
guided-decision machinery as the Phase 4 suite, no checker-retry loop).
Raw trace: `benchmark/coding_suite/runs/plan_probe_afm.jsonl`.

| task | base calls | plan calls | base tokens† | plan tokens† | pass |
| --- | --- | --- | --- | --- | --- |
| edit_01_rename_constant | 17 | 17 | 516 | 657 | ❌/❌ |
| edit_02_add_field | 17 | 3 | 581 | 463 | ❌/❌ |
| edit_03_fix_typo_string | 17 | 17 | 536 | 558 | ❌/❌ |
| edit_04_delete_function | 17 | 2 | 514 | 398 | ❌/❌ |
| edit_05_write_new_file | 17 | 1 | 593 | 326 | ❌/**✅** |
| edit_06_json_config_update | 17 | 17 | 488 | 575 | ❌/❌ |

† **Accounting caveat**: `tokensUsed` sums each actor's final `Situation`
size, not cumulative tokens across decisions. Cumulative per-decision
accounting must land before any published tokens/task claim (suite-runner
fix).

### Findings

1. **Convergence dominates, not close-out.** In 3/6 tasks the real model
   thrashed until the 16-round budget in BOTH arms — the frontier can only
   terminate early once criteria actually pass. Where verification did pass,
   termination was dramatic: **17 → 1 call (edit_05, and it PASSED where
   baseline failed)**, 17 → 2, 17 → 3.
2. Aggregate: **−44% LLM calls** even against a baseline that failed every
   task. Tokens ≈ flat (−8%) due to the accounting caveat.
3. **Baseline regression suspect:** all-baseline-fail contradicts Phase 4
   (4/6 edit passes with retries). Two uncontrolled deltas vs Phase 4: (a)
   this probe omits the checker-retry loop; (b) context fragments now carry
   role prefixes (`asst:`/`tool:` — the messages-codec protocol change),
   which alters the AFM prompt format. An A/B of prefix-on/off is required
   before attributing the regression.

### Verdict

Mechanism confirmed end-to-end on a real local model — mechanical
verification, pure policy, early termination, and one case where the plan arm
PASSED while the identical baseline burned its whole budget. But the probe
falsifies any assumption that close-out elimination alone moves real-model
tokens/task: **the binding constraint on-device is decision convergence**,
which is exactly what the full ADR 0009 design (declared acceptance criteria
in-frame every call + tight mechanical failure feedback + decomposition)
targets. Next: cumulative token accounting, prefix A/B, then re-probe.

---

## Follow-up round — cumulative accounting + prefix A/B (2026-08)

### 1. Cumulative token accounting landed

`Situation.tokensUsed` is per-decision; summing final situations measured
"last cut size", not spend (the §accounting caveat above — now fixed).
`CumulativeTokenMeter` observes each decision's projection at handler entry:

- `TaskResult.cumulative_tokens` added to the production suite runner
  (`benchmark/coding_suite/runner.dart`) and JSONL traces.
- `PlanRow.cumulativeTokens` in `plan_frontier_arms.dart`.

Impact: real per-task spend on AFM is **~8.6–11k tokens** where the old field
reported ~500 — a 20× gap. All published tokens/task numbers before this fix
are undercounts and must be re-derived from re-runs.

### 2. Role-prefix A/B: prefixes exonerated

Re-ran baseline arm on all 6 edit tasks with role tags OFF (exact Phase-4
wire format, `--no-role-tags`). Result identical: 6× FAIL, 17 calls each,
same thrash pattern. Trace:
`runs/plan_probe_afm_notags.jsonl`.

### 3. Real culprit found (pre-existing, not ours)

Probe logs show nearly every `write`/`read`/`list_dir` call failing with
`Invalid argument(s): Path …` (fs-jail rejection). Cross-checked against the
**Phase 4** `afm_run.log`: the same error appears **156 times** there. So the
all-fail baseline regression is not the messages codec, not the role
prefixes, and not the arm machinery — it is a pre-existing model/harness
interaction: AFM emits paths that the jail rejects (likely absolute or
root-escaping paths), then thrashes. Phase 4's 4/6 edit passes were rescued
by the checker-retry loop this probe intentionally omits.

### Next (in order)

1. Capture the full untruncated path-rejection message (xs_fm logger
   truncates); classify escapes-vs-malformed from real traces.
2. Harness-side mitigation candidates (seam 3 only): have `list_dir` return
   jail-relative paths; normalize absolute-inside-root paths in `resolve`;
   bounce-with-explanation errors naming the expected relative form.
3. Re-probe plan arm with the verifier feedback loop active — tight mechanical
   failure feedback is precisely what should stop the thrash early.
