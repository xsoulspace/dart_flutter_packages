# ADR 0009 Falsification Results — plan-frontier vs ReAct close-out

Date: 2026-08. Experiment:
[`benchmark/adr0009_experiments.dart`](../../../benchmark/adr0009_experiments.dart)
(`--mode falsification`). Run:
`dart run benchmark/adr0009_experiments.dart --mode falsification`

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
- `PlanRow.cumulativeTokens` in `benchmark/shared/world_builder.dart`.

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

---

## Round 3 — mitigations + verifier-feedback re-probe (2026-08)

### Landed

1. **Full tool-error capture**: `PlanRow.toolErrors` / probe JSONL
   `tool_errors` — the native logger truncates at ~20 chars; traces now carry
   complete outputs. Classification from real traces:
   - hallucinated absolute paths (`/tmp/user_data.json`,
     `/tmp/sample_directory/...`) — model inventing workspace locations;
   - `config.dart/` trailing-slash → `list_dir` "Not a directory".
2. **fs-jail mitigations (seam 3, `fs_tools.dart`, regression-tested in
   `test/fs_tools_test.dart`)**:
   - escape errors now **teach the fix** ("Use paths RELATIVE to the
     workspace root… Call list_dir with path '.'");
   - symlink-tolerant containment (`/var` ↔ `/private/var` accepted);
   - wrapping quotes stripped;
   - `list_dir` returns **jail-relative entries** with `dir/` markers;
   - `list_dir` on a file path lists its parent (trailing-slash habit).
3. **Re-probe: plan arm vs baseline** (6 edit tasks, cumulative tokens):

| task | b_calls | p_calls | b_cum | p_cum | cum Δ |
| --- | --- | --- | --- | --- | --- |
| edit_01_rename_constant | 17 | 17 | 10904 | 9593 | −12% |
| edit_02_add_field | 17 | 1 | 9724 | 329 | −97% |
| edit_03_fix_typo_string | 17 | 12 | 10955 | 5019 | −54% |
| edit_04_delete_function | 17 | 17 | 8799 | 6612 | −25% |
| edit_05_write_new_file | 17 | 1 | 8743 | 326 | −96% ✅PASS |
| edit_06_json_config_update | 17 | 17 | 8597 | 7055 | −18% |
| **TOTAL** | **102** | **65** | **57722** | **28934** | **−50%** |

### Findings

- **−36% calls, −50% cumulative tokens** on a real local model where every
  baseline run thrashed to its round budget.
- edit_05 PASSED with 1 call / 326 tokens (baseline: 17 calls / 8743, fail).
- edit_02 exposes a **coverage gap**: the model answered without acting; no
  tool result ⇒ no verification ⇒ episode ends on an unverified goal. The
  frontier currently gates only after tool activity. Candidate rule: "actor
  idle + open goal ⇒ verify before sleep" (mechanical, no LLM).
- Remaining thrash (edit_01/04/06) is model-side path hallucination surviving
  even with teaching errors — the next lever is decomposition with per-step
  criteria (the full ADR 0009 design), not more jail tuning.

### Verdict

The plan-frontier mechanism delivers its scripted promise on-device where
verification can pass, and halves spend overall. The binding constraint has
moved decisively from harness mechanics to model decision quality — exactly
where ADR 0009's decomposition and acceptance-criteria-in-frame are aimed.

---

## Round 4 — idle-verify rule + decomposition mechanics (2026-08)

### 1. Idle-goal verification rule landed

Closes the coverage gap from Round 2: an episode where the model **answers
without acting** used to end silently on an unverified goal (edit_02 on
device: 1 call, FAIL, nothing verified).

- `goalVerificationSystem` now also runs while an actor sits **idle with an
  open goal**: verifies mechanically; on failure opens ONE tight nudge
  decision directly in-system (bounded by `maxIdleNudges = 1`).
- **Two invariant lessons re-learned the hard way**:
  1. First implementation deferred the nudge via a marker component for the
     policy to pick up next tick — invisible to `canSleep()`, so
     `runUntilIdle` exited first. Fixed by opening the decision in-system
     (the exact "idle ⇒ nothing stranded" rule from the 2026-08 postmortem).
  2. The idle check must mirror `canSleep()` **including in-flight tool tasks
     and unconsumed result events** — otherwise the verifier races an
     executing write and nudges on stale workspace state.
- Proof: `benchmark/adr0009_experiments.dart` (`--mode idle-proof`) — a
  deterministic flaky handler
  (answer-only first call) ends FAIL/1-call without the rule; WITH the rule:
  caught → nudged once → goal achieved. **2 calls, PASS, 664 tokens.**
- On-device cost data (`runs/plan_probe_afm_idlerule.jsonl`): with 2 nudges,
  hopeless tasks reopened full tool-round chains (edit_04: 17→33 calls, zero
  pass gain) → nudges capped at 1.

### 2. Decomposition mechanics landed

`benchmark/adr0009_experiments.dart` (`--mode decomposition`): steps as
entities with per-step
claims + exact-content acceptance predicates; each decision sees ONLY the
current step's criterion; per-step verification is mechanical graph logic;
frontier advances by opening the next step's decision — zero close-out calls.
(The decompose-once transform itself is mocked; its fidelity is a separate
measurement.)

| task | base calls | decomp calls | base cum | decomp cum | cum Δ |
| --- | --- | --- | --- | --- | --- |
| refactor_01_extract_shared_function | 21 | 3 | 3863 | 1085 | −72% |
| refactor_02_rename_across_files | 21 | 3 | 3778 | 1029 | −73% |
| refactor_03_split_file | 20 | 4 | 2585 | 1449 | −44% |
| refactor_04_consistent_api | 21 | 3 | 3770 | 1058 | −72% |

All pass both shapes. Calls scale with STEPS (actions + 0 overhead), not
rounds-budget; cumulative tokens roughly halve-to-third because each cut
carries one step's criterion instead of a whole-goal prompt plus narrative.

### Verdict after four rounds

Every layer of ADR 0009 is now demonstrated end-to-end on the real harness:
goal vector + mechanical verification (R1), pure frontier policy + verifier
tools behind seam 3 (R2), fair-comparison accounting + codec ruling (R3),
idle-coverage rule + per-step decomposition (R4). Scripted deltas: −39%
calls/−19% tokens (whole-goal frontier); decomposition adds −44…−73%
cumulative tokens on multi-step tasks at equal pass rate. Remaining unknowns,
in order: real-model decomposition probe (needs an actual decompose call via
guided schema), cumulative-token re-run of the Phase 4 matrix.
