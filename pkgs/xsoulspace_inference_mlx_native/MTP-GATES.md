# MTP-GATES.md â the frozen gates for the MTP / adapter lines (2026-10-21)

One screen. Read it before running any MTP or adapter experiment in this
package. Same discipline as [POWER.md](POWER.md) (the power laws) and
[TRAIN-GATES.md](TRAIN-GATES.md) (the nursery training gates): **a threshold
changes only by editing this file BEFORE the first run of that arm â never
after seeing results.** A threshold written after seeing data is a knob; written
before, it is a verdict generator
([META-LESSONS.md](bench/nursery/META-LESSONS.md) lesson 1).

Why a separate file: `bench/` is gitignored in this package
(`.gitignore`: `/bench*/`), so a gate written under `bench/` is not versioned
and cannot bind a later run. This file is tracked, so the freeze is durable.

Line naming: **Line J** = MTP on a real trunk (the "MTP count" line).
**Line K** = the swappable-adapter line. Both are read by
`tool/nursery/mtp_*.py` and by the native Rust port.

## What the previous arm measured (the evidence these gates react to)

Recorded in `bench/nursery/experiments/RESULTS-2026-10-20.md` Â§5 and
`RESULTS-part2.md` Â§8 (local, gitignored). The Qwen3-0.6B-bf16 trunk, one
MLP-only draft head, corpus = real Dart source:

| steps | accept vs truth | accept vs **trunk** | trunk top-1 | derived speedup |
| ----- | --------------- | ------------------- | ----------- | --------------- |
| 500   | 0.478           | 0.267               | 0.399       | 1.41Ã           |
| 1500  | 0.939           | 0.337               | 0.399       | 1.42Ã           |
| 3000  | **0.999**       | **0.359**           | 0.399       | 1.22Ã           |

The head **saturates on truth (0.999) and still disagrees with the trunk 64% of
the time.** The trunk itself is only 39.9% accurate on this corpus. So the
head is a _better_ predictor of the corpus than the trunk is â and that is
exactly why it is not accepted. The previous arm trained the head against the
**corpus truth**, while the gate measures **agreement with the trunk**. The
objective and the metric were different quantities.

**A second, structural flaw in the old measurement.** The old arm was
teacher-forced on _corpus_ text: the head was fed the trunk's argmax
`a_t`, but the acceptance target (the trunk's next argmax `a_{t+1}`) was
computed with the **true** corpus token in the prefix, not with `a_t`. In a
real greedy decode the prefix IS the trunk's own output, so those two agree
and the mismatch does not exist. The old `accept_vs_trunk` therefore measured
a quantity that does not exist at decode time. Both flaws point the same way:
**the head must be trained and measured on the trunk's own greedy path.**

## Line J â MTP on a real trunk

The MTP shape: one or more cheap draft heads read the trunk's hidden state
and the trunk's own last token, and propose the token(s) after it. The trunk
then verifies them in ONE batched forward. Why this can pay where Line A
(draft-model speculation) did not: the draft costs a small MLP, **not a second
model read** â and on a memory-bound device one batched trunk forward over
`K+1` positions costs about the same weight read as one position.

### J-G1 â acceptance (the load-bearing number)

Measured **decode-consistently**: the head is fed the trunk's own greedy path
and compared against the trunk's own next argmax on that same path. The
metric is P(draft == trunk's next token), NOT P(draft == corpus truth).

**Threshold: acceptance â¥ 0.60** (inherited unchanged from the previous arm's
frozen gate â it is NOT moved, it is re-measured on a correct measurement).

### J-G2 â effective speedup

Derived from measured forward costs, never assumed:
`tokens_per_cycle = 1 + accepted_prefix`, `cost_per_cycle = t_verify(K+1
positions) + Î£ t_head_j`, `speedup = tokens_per_cycle / cost_per_cycle Ã
t_ar(1 position)`.

**Threshold: effective speedup â¥ 1.5Ã AR.**

The Python timings are compute/launch-bound and are a **lower bound** on the
device's real ratio; the native Rust port is the authority for this number
(J-G4). A Python arm may not claim J-G2 on its own.

### J-G3 â MTP count (the "count applied" arm)

`count = K` = the number of chained draft heads (DeepSeek-V3 shape: head _j_
reads head _jâ1_'s hidden state and the previous head's proposed token).
A count is **adopted** only if, at equal measured cost, the accepted-prefix
length grows faster than the extra head cost. Concretely, a count is adopted
when **tokens per cycle at count K > tokens per cycle at count Kâ1** at the
same acceptance, i.e. the marginal head buys more than it costs.

**Threshold: adopted count â¥ 2** (count 1 is the previous arm's arm). If no
count beats count 1 on tokens-per-cycle, the count line closes with data.

### J-G4 â native Rust port (the "extreme performance" arm)

The native port is the authority for J-G2. Its own gate is exactness:

**Threshold: the native MTP decode is token-exact against plain greedy**
(the same law Line A's native port holds: greedy verification is token-exact).
This is a correctness gate â never power-conditioned.

Reported speedup is an interleaved same-process A/B (plain greedy vs MTP,
same prompt, same process, arms interleaved), with the power state recorded
beside it. Absolute tok/s on a machine whose charge current is not real is a
non-claim ([POWER.md](POWER.md) charge-current hole); the RATIO is the
measurement.

### J-G5 â power law

Every number carries a power snapshot with the real `Amperage` (not the
`pmset` source flag). Acceptance numbers are hardware-independent and are not
power-conditioned. Speedup ratios are interleaved same-process.

## Line K â the swappable-adapter line

### K-G1 â the swap is real and reversible

An adapter set must be **swappable at runtime** with a durable digest, and a
swap must be **reversible** (adapter off â byte-identical to base). The
merge surface already enforces the hard-error rule (a target absent from the
base is an error, never a skip).

**Threshold: adapter-off == base byte-for-byte; adapter-on changes the
output; swap-back restores the base output exactly.**

### K-G2 â cache invalidation is not optional

A merged weight set is a DIFFERENT model, so every cached prefix computed
under the old weights is stale. The cache key must include the adapter
digest.

**Threshold: a cache hit under a changed adapter digest is impossible** â
proven by a test that swaps the adapter and shows the prefix cache misses.

### K-G3 â the capability question (the honest one)

The previous arm's measured verdict: an adapter on Qwen3-0.6B moved
**format** compliance (0.50 â 0.83 body rate at minimal context) and **zero**
compilable output. "The adapter is the right mechanism for the wrong base."

**Threshold for adopting the swappable-adapter line as a capability: the
adapter must move a MEASURED task metric on a base that can do the task.**
Format-only movement is recorded as format-only and does not open the line.

### K-G4 â the base must support it

The current merge surface refuses quantized bases (a merge into a packed
weight would need dequantize â merge â requantize). The product checkpoints
are 4-bit. An adapter experiment on a 4-bit base therefore needs a
dequantizeâmergeârequantize path, or a plain-weight base, and the choice must
be stated with the measurement â it is not a detail.

## Pre-registered failure readings (written BEFORE any arm runs)

The point of pre-registration is that a failure becomes information. These
readings are fixed now.

1. **J-G1 fails (acceptance < 0.60).** Then the question "can a cheap head
   imitate this trunk?" is answered NO at this scale, and the answer is
   final for the MLP-head shape: the head is not given the information the
   trunk has. The remaining live question is a head WITH attention (a full
   block, DeepSeek's shape) â a different architecture, not a retune. The
   line does NOT continue by re-running with more steps: the previous arm
   already showed truth-accuracy saturating at 0.999 while acceptance
   plateaued at 0.359, so more steps on the same objective cannot move it.
2. **J-G1 passes but J-G3 fails (no count beats count 1).** Then the
   technique works at count 1 and the count line closes with data. No
   count-2+ work is bought.
3. **J-G2/J-G4 fail (no speedup natively).** Then MTP is an acceptance
   technique without a speed payoff on THIS hardware, and the recorded
   verdict is that. The acceptance number stays useful for a hardware with
   more bandwidth.
4. **K-G3 fails (format only).** Then the swappable-adapter line stays a
   _surface_ (K-G1, K-G2) and does not claim capability. The next base must
   be one that can do the task, or the task must be narrowed to one the base
   can already do.

## Non-claims

- Passing J-G1 is eligibility for a native port, not a speedup claim.
- Passing J-G2 on Python timings is not a speedup claim (J-G4 is the
  authority).
- A gate pass claims nothing about the harness, the world, or product
  behaviour; it is a property of one model, one corpus, one device.
- Every number here is one machine, one model, one corpus, one seed unless
  stated otherwise.

---

# PART 2 â the next arms (frozen 2026-10-21, BEFORE any next run)

Part 1 froze the gates for the arms that ran on 2026-10-21. Part 2 is the
corrected reading of those results **plus** the gates for the next arms. It is
frozen before the next run, by the same law: a threshold written after seeing
data is a knob.

## Corrections to the 2026-10-21 record (verified 2026-10-21)

These are corrections of RECORD, not new results. Each is reproducible from
the tree; the evidence is named so a later reader can re-derive it. The
2026-10-21 verdicts are not deleted â they are restated where the reason was
wrong, because a wrong reason is what sends the next agent to the wrong arm.

| #    | The record says                                                                                                                                                   | The verified finding                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Evidence                                                                                       |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| C-1  | "the physics that makes MTP attractive is real: the batched trunk forward is nearly flat in k" (0.688/0.682/0.679/0.709/0.669/0.680 ms for 1/2/3/4/6/8 positions) | **Not flat, and the series has no producing artifact in the tree.** The same document's forced-execution table measures **27.18 ms** for the same 1-position body forward â 39x the claimed 0.688 ms. The native bench's own forced numbers give verify(2)/verify(1) = **14.07/10.06 = 1.40**, i.e. a **4.01 ms marginal cost per verified position** against a 12.00 ms AR token.                                                                                             | `RESULTS-mtp-2026-10-21.md:184-186` vs `:40-41`; native `MtpStats.verify_us`                   |
| C-2  | acceptance 0.124 is "the head SHAPE, not the target, is the binding constraint" â final for the MLP-head shape                                                    | **Not established: the head was OVERFIT, so the shape was never tested.** Arm C scores **0.9015 in-sample** on its own training prompts and **0.1235 held-out**. A bigram table fitted on the same training pool scores **0.1483 held-out â above every arm**. The arm measured a memorizing head, not a capacity limit.                                                                                                                                                       | reproduced from `/tmp/mtp_arms_c1/armC.head.safetensors` + `/tmp/mtp_records_bf16.pkl`, no GPU |
| C-3  | "the arm matrix was run twice, independently, and reproduced to 4 decimal places"                                                                                 | **One run, two copies.** `bench/â¦/mtp-2026-10-21/arm{X}.json` are byte-identical to `/tmp/mtp_arms_c1/arm{X}.json`, same `when_utc`, same power block. The determinism claim is untested.                                                                                                                                                                                                                                                                                     | `cmp` on all four arms                                                                         |
| C-4  | "the PERM adapter â¦ stops answering in the clause label set at all; every sample is a miss"                                                                      | **The artifact contradicts the prose.** `outside_label_set = 0` on that cell means **no** completion fell outside the label set. The scorer is a bare substring search (`low.find(lab)`), so `abandoned`âdone, `transaction`âaction, `satisfaction`âfact+action, `reopened`âopen. The **magnitude** of the â0.847 is a scoring artifact of the same class as the think-echo defect; the direction (an adapter that does not transfer) is real, the number is not yet a number. | `adapter-set-capability-2026-10-21.json`; `adapter_set_capability.py:191-197`                  |
| C-5  | "unreachable at ANY acceptance" (0.91x at p=1.0)                                                                                                                  | The **arithmetic is right for the port and wrong for the gate.** The port commits `max(accepted_prefix, 1)` tokens per round (1 token always, at K=1) while the gate's formula assumes `1 + accepted_prefix`. The recorded 0.91x is the port's own accounting; under the gate's formula the same components give 1.82x. The port cannot beat AR **by construction**, because a depth-0 draft competes with the token the trunk already has.                                    | `qwen_mtp.rs:582-587, 722-728, 757-788` vs `MTP-GATES.md:68-70`                                |
| C-6  | "J-G3 FAILS: no count beats count 1"                                                                                                                              | **Contradicts its own artifact.** `tokens_per_cycle_by_count = [1.1393, 1.1539, 1.1539]` â count 2 > count 1, and the artifact's `J-G3_best_count_by_tokens_per_cycle` field names count 2. The gate as written compares tokens-per-cycle while **counting no head cost** (3.13 ms/head/round), so its adoption test is under-specified.                                                                                                                                       | `RESULTS-mtp-2026-10-21.md:129-136` vs the count-3 run's fields                                |
| C-7  | depth acceptance 0.1393/0.0146/0.0000 is "arm C (the best arm)"                                                                                                   | That is a **different model** (count=3: the loss sums all three depths, 13.44 vs 0.46). Arm C at count=1 is 0.1235. Quoting a count-3 number as the count-1 arm conflates two models.                                                                                                                                                                                                                                                                                          | `RESULTS-mtp-2026-10-21.md:121-127`                                                            |
| C-8  | "12 held-out prompts x 192 positions = 2160 positions"                                                                                                            | The artifact says **2292** (12 x 191). The prose number is wrong in both parts.                                                                                                                                                                                                                                                                                                                                                                                                | `armX.json:positions_measured`                                                                 |
| C-9  | `accept_teacher` is reported as a second, independent number                                                                                                      | At count=1 it is **provably identical** to `accept_self` (both read `toks[:n]`), and all four artifacts show `self == teacher` exactly.                                                                                                                                                                                                                                                                                                                                        | `mtp_retarget.py:497-511`; all four arm JSONs                                                  |
| C-10 | the swappable-adapter capability is on "a base that can do the task"                                                                                              | The measured +0.153 is on the **python mlx-lm runtime-adapter path**. The Rust surface **cannot load that artifact at all**: `mlx_lm` writes `lora_a`/`lora_b`, the Rust loader accepts only PEFT `lora_A.weight`/`lora_B.weight`. So the +0.153 is not a native-surface capability result.                                                                                                                                                                                    | `mlx_lm/tuner/utils.py:152` vs `native/mlx_native/src/lora.rs:183-195`                         |

### What the corrections do NOT change

- The **native port is token-exact** against plain greedy (0 divergences). Unaffected.
- The **measured 0.42x** of plain greedy on this device. Unaffected â it is a
  measurement.
- The **mechanical half** of the adapter line (swap is byte-for-byte
  reversible, the cache key carries the adapter digest, a quantized base is
  refused at bind). Unaffected; it is a property of `lora_set.rs`.
- **MTP as a speed technique is not rescued by C-1..C-7.** With the measured
  non-flat verify (4.01 ms marginal per position) and the port's own
  accounting, the 1.5x gate stays unreachable at any acceptance: break-even
  needs acceptance >= 0.433 even after the token-accounting correction. The
  corrections change **why** the line is closed and therefore **what is worth
  buying next** â not the closure itself.

## Line J' â MTP: what, if anything, is worth another arm

**J'-G0 (decides whether Line J' exists at all).** Measure the trunk's body
forward at 1/2/4/8 positions, forced-eval, **excluding** the tied projection,
natively, and the marginal cost per position.

**Threshold (three bands, fixed before the run):**
`body(8)/body(1) <= 1.15` â the forward is **flat** â rewrite the cost model
and acceptance becomes the only blocker. `>= 1.5` â **not flat** â MTP-as-speed
is closed on **physics** for any acceptance, and **no further MTP arm is
bought**. The middle band `1.15 < ratio < 1.5` is **ambiguous**: re-derive the
marginal cost by the second method (body-only at 2/4/8 positions with the tied
projection excluded from the timer) before spending any training time; a
middle-band result does NOT authorise an MTP arm.

**Why this gate is load-bearing.** Under the port's own token accounting a
depth-0 draft buys no token (C-5), so the speed verdict is a _physics_ verdict
about the marginal cost of a verified position. The 2026-10-21 native numbers
give verify(2)/verify(1) = 14.07/10.06 = 1.40 â a middle-band hint, but the
verify timer INCLUDES the tied projection over the verified positions, so it
overstates the body marginal. Decomposing the projection out is exactly what
J'-G0 measures.

**Prior: the line stays closed.** The flatness series that argued the opposite
(C-1) has no artifact. Budget 45-60 min.

**J'-G1 (acceptance, re-asked correctly).** The threshold moves from a fixed
0.60 to **the trivial baseline measured on the same items**: held-out
acceptance must exceed the bigram baseline **+ its prompt-clustered CI
half-width**. Measured at n=2292: bigram **0.1483**, copy 0.0851, constant
0.0227.

**Why the threshold moves.** J-G1's 0.60 was frozen against the OLD arm's
off-policy metric, which was never comparable to 0.60. The 0.60 number stays
valid **for the old arm**; it is not a threshold for a new arm whose metric is
different. This is a change of arm, not a change of a threshold under
measurement.

**J'-G2 (the head must generalize, or the arm is void).** Every head reports
**in-sample and held-out** acceptance on the same items. If in-sample >= 0.85
while held-out is below the J'-G1 baseline, the arm is **invalid** (the head
memorized; mechanics unproven, features lack a shared signal) â a
_mechanics_ failure, not a technique failure, and it does not close the shape.

**J'-G3 (token accounting, restated in the port's units).** A speed claim uses
the port's own accounting: `committed_tokens_per_round = max(accepted_prefix,
1)`, plus the per-round cost of the verify, the head chain, and the resync.
**No speed claim may use `1 + accepted_prefix` while the port commits
`max(accepted_prefix, 1)`.** The port's structure is itself the defect: a
depth-0 draft competes with the token the trunk already holds, so the head's
cost buys nothing. Fixing the structure (commit the trunk's own token AND the
accepted drafts) is a **prerequisite** to any MTP speed claim, and it is
pre-registered here as **not yet done**.

**J'-G4 (head shape).** An attention-equipped head is **not bought** under
this gate. Prior: the cost structure is the killer, and attention raises
per-head cost without touching it. It becomes eligible only if J'-G0 returns
`<= 1.15` AND J'-G1 passes AND the port's structure is fixed.

## Line K' â the adapter capability and selectivity, re-asked

**K'-G1 (strict scoring).** A completion is correct only if, stripped, it
**equals** a label (word-boundary exact). A substring hit is a MISS. Every
earlier number scored under the substring rule is **not a claim**. This
retires the C-4 defect at the source.

**K'-G2 (reproducibility).** The trained adapter, its `adapter_config.json`,
and the **per-item outcomes** are kept as artifacts. The cached-adapter branch
is disabled or logged â "a trained adapter is CACHED in the work dir" means a
re-run may silently reuse a different adapter than the artifact describes, and
the 2026-10-21 adapter directory no longer exists.

**K'-G3 (a non-degenerate second task).** The second task's label set is
**disjoint** from the first's, and its majority class is **< 0.5** with every
label represented. The clause task (0.860 majority, `action` = 0 examples) is
**retired as evidence**.

**K'-G4 (conditioning).** The task signal is an explicit tag in the prompt, at
train AND test time; `mask_prompt=True` (loss on answer tokens only); the tag
is not in the label vocabulary, so it cannot be scored as an answer. One
adapter, both tasks. This is the arm that decides whether **one
task-conditioned adapter** replaces the whole "set" idea.

**K'-G5 (no unconditional prior).** Per-task prediction histograms: no single
label may hold > 90% of a task's predictions. This is the direct test of the
mechanism the 2026-10-21 arm proposed and could not separate from a scoring
artifact.

**K'-G6 (interference, cost-corrected).** Cross-task damage is measured
against the **strongest trivial baseline** of the target task, with the
strict scorer, and the target task's own label set as the only legal answers.

### Pre-registered readings for Line K' (written before the run)

1. **K'-G1+G4 pass, K'-G5+G6 pass** â selectivity IS recoverable by
   conditioning. The product shape is **one task-conditioned adapter per
   base**, not a set of swappable specialists. The set surface is then
   over-built and should be demoted.
2. **K'-G1+G4 pass, K'-G5 or K'-G6 fail** â conditioning is insufficient; the
   prior is unconditional at the weight level. The honest product is **one
   adapter per task, never swapped on a resident base** â the 2026-10-21
   verdict stands, now on a strict scorer and a non-degenerate task.
3. **K'-G1 fails (no adapter beats the trivial baseline under strict
   scoring)** â the 2026-10-21 +0.153 was a scoring artifact; the adapter
   line closes on **capability**, not on selectivity, and the mechanical
   surface stands alone.
4. **K'-G2 fails (artifacts not reproducible)** â no capability claim may be
   made in either direction until it is.

## What is NOT bought with the next 5 hours, and why

- **An MTP attention head.** J'-G4: the cost structure is the killer and
  attention does not touch it.
- **More MTP acceptance arms on the current head.** J'-G2: it is invalid
  (in-sample 0.90).
- **A 4-bit dequantâmergeârequant path.** No product consumer, no FFI
  surface, and the requantization error is the same order as the adapter
  delta (âÎWâ/âWâ median 5.0%) â it would void the measured +0.153. The
  measured capability is on the **runtime** path; the native merge surface
  refusing a 4-bit base is correct, not merely conservative.
- **More adapter _shapes_ (rank, target modules).** K'-G1..K'-G4 must pass
  first; a shape sweep on an unmeasured base optimizes an unknown.

## The 5-hour budget (GPU work is serial: two concurrent GPU jobs halve

## throughput)

| #   | Arm                                                                                                        | Decides                                                                  | Wall clock | GPU        |
| --- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ---------- | ---------- |
| 1   | **J'-A** native body-forward marginal cost (1/2/4/8 positions, forced, projection excluded)                | whether Line J' exists at all                                            | 45-60 min  | yes        |
| 2   | **K'-A** strict re-score of the adapter matrix (retrain, strict scorer, per-item + adapter artifacts kept) | whether +0.153 survives strict scoring; whether â0.847 is real           | 30-45 min  | yes        |
| 3   | **K'-B** conditioned single adapter over two disjoint-label tasks (`mask_prompt=True`, saved completions)  | whether selectivity is recoverable â the product-shape question          | 60-90 min  | yes        |
| 4   | **K'-C** non-degenerate second task (labels disjoint from PERM, majority < 0.5, every label present)       | whether the interference reproduces on a non-degenerate task             | 45-60 min  | mostly CPU |
| 5   | **E** prefix-cache invalidation (engine-owned weight identity) **+ the Rustâmlx adapter-format bridge**    | whether a swappable adapter is usable at all (C-10 says it is not today) | 60-90 min  | no         |
| 6   | **D** durable ledger: tracked verdicts, corrections, evidence paths, non-claims                            | whether the negatives survive a clone                                    | 30 min     | no         |

Total 4.5-5.0 h with the GPU arms serial. Items 1-3 are the **decision** arms;
4-6 are the **durability** arms. If the GPU arms overrun, item 1 is the first
to drop (the closure is already re-derivable from existing native data, C-1)
and item 5 is the one that must NOT drop (it is the gap that makes the
adapter feature real).

---

# PART 3 â the K' control-contrast amendment (2026-10-21)

Part 3 is a **defect fix** in the K' gate definition, made after the K' run
and recorded here with its measured reason. It is NOT a threshold change and
NOT a criterion change: no threshold moves, and the Part 2 readings stay in
force. It is filed in this file, in this format, because a gate that was
under-specified must be repaired where its readers will look â and the
repair must be visible, not silent.

## The defect (C-11)

**K'-G1..K'-G6 never encoded the control contrast, so reading 1 was
unfalsifiable as encoded.**

- The words `untagged`, `permsolo` and "control" appear **zero** times in
  Parts 1-2 of this file. The K' gate defines one arm and reads one arm.
- `evaluate_gates` (`tool/nursery/adapter_conditioning.py`) reads
  `arms["cond"]` exclusively. The other arms are computed and scored, and
  **no gate value can change because of them**.
- Yet the arm was _designed_ as the control: `adapter_conditioning.py`
  declares `untagged` as _"the control: it isolates the TAG from the
  multi-task training data"_. The design encoded the contrast; the gate did
  not.

Consequence: reading 1 â _"selectivity IS recoverable by conditioning; the
product shape is ONE task-conditioned adapter per base"_ â would have fired
**unchanged** even if the conditioning had contributed nothing, because
nothing in the gate contrasted `cond` with a control.

## K''-G1 (the control contrast) â frozen 2026-10-21, after the K' run

**The gate arm must beat the control arm by more than the paired
uncertainty, on at least one task, or the attribution is not established.**

- Gate arm: `cond`. Control arm: `untagged` (same two-task training, no
  tag). The comparison is **paired** (same items, same split) and uses an
  exact two-sided McNemar test; the reported quantity is the paired
  difference with a 95 % CI.
- The comparison is computed by `tool/nursery/fast_score.py` from the cached
  per-item completions â **no GPU, no retrain**. A scoring question needs the
  JSONL, not the model.

**Readings (in force):**

1. **K''-G1 passes** (the tag's paired effect is significant, and positive)
   â _"recoverable BY conditioning"_ is established, and the product shape is
   **one task-conditioned adapter per base**.
2. **K''-G1 fails** (the tag's paired effect is not distinguishable from
   zero, or is negative) â selectivity is recoverable **by multi-task
   training** â the legal label set already in the prompt is the conditioning
   signal â and the tag is **not load-bearing**. The product shape is
   **one adapter trained on multiple tasks, untagged**. The Part 2 reading 1
   stands only in its _product-shape_ half; its _causal_ half is withdrawn.
3. **The control arm is missing** â no attribution may be claimed in either
   direction; the reading is unfalsifiable and stays unfalsifiable until the
   arm exists.

Reading 2 is the **measured** outcome on this run:

| comparison      | discordant | cond-only | control-only | Î (cond â control) | 95 % CI            | p (paired, exact) |
| --------------- | ---------- | --------- | ------------ | ------------------ | ------------------ | ----------------- |
| untagged / perm | 28 / 150   | 10        | 18           | â0.0533            | [â0.1219, +0.0153] | 0.185             |
| untagged / veto | 17 / 150   | 8         | 9            | â0.0067            | [â0.0605, +0.0472] | 1.000             |
| permsolo / perm | 25 / 150   | 2         | 23           | **â0.1400**        | [â0.2014, â0.0786] | **<0.001**        |
| permsolo / veto | 102 / 150  | 96        | 6            | **+0.6000**        | [+0.5095, +0.6905] | **<0.001**        |

â **K''-G1 FAILS against the tag, and the second control names what IS
load-bearing.**

- The **tag** is not: `untagged` (the same two-task training, no tag) is at
  least as good as `cond` on both tasks, neither difference is significant,
  and both point estimates are negative. The tag is **not load-bearing**; the
  legal label set already in the prompt is the conditioning signal.
- The **multi-task training data** is: `permsolo` differs from `cond` by one
  variable (one task instead of two) and the differences are large and
  significant in both directions â it loses 0.60 on the task it never saw
  (and falls **below** the trivial baseline, 0.1733 vs 0.2733) and gains 0.14
  on the one it did.

The honest product shape is therefore **one adapter trained on all tasks,
untagged** â a set of swappable specialists is not supported, and neither is a
tagged one.

### K''-G2 (the option-list contrast) â frozen 2026-10-21, after the K' run

**The gate arm must still transfer when the prompt names NO task.** If it
does, the option list is not the mechanism of transfer.

- Control arm: `shared` â both tasks, no tag, and **one option list for
  both** (the union of the two label sets), so the prompt carries no task
  signal. Single variable against `untagged`.
- The read is a pure function of the cached completions (no GPU).

**Reading (in force):**

1. **`shared` beats the matched trivial baseline on BOTH tasks** â the
   mechanism is the **input text**; the label set in the prompt need not name
   the task, and the honest product is "a prompt that states the answer
   space".
2. **`shared` fails on either task** â the mechanism is the **option list**,
   and the prompt MUST name the task.

Reading 1 is the **measured** outcome: `shared` scores 0.7867 (perm) and
0.7133 (veto) against matched trivial baselines of 0.5467 and 0.2733 â i.e.
+0.2400 and +0.4400, with no unconditional prior (top-label 0.560 / 0.273).
Paired against `untagged`: perm Î +0.0867, 95 % CI [+0.0177, +0.1557],
p=0.024; veto Î +0.0667, CI [â0.0153, +0.1486], p=0.154.

**The mechanism is visible in the diagnostics, not only in the totals.** The
`shared`/veto cell has `outside_label_set = 9`, and **all nine are `abstain`**
â a perm-family label â on veto items whose gold is `no_grant`. The model
read the text, decided to refuse, and named the refusal in the wrong
family's vocabulary. (That `abstain` and `no_grant` are the same decision is
a human reading of the label set; the measured facts are the nine out-of-set
completions and their gold labels.)

**What the option list is worth: a refinement.** A task-specific list is
worth +0.087 on perm (p=0.024) and +0.067 on veto (p=0.154). So the honest
product is "a prompt that states the answer space" â and the answer space may
be **shared**, at a cost of roughly 7â9 points, most of it vocabulary rather
than decision quality.

**Non-claims.** One model, one corpus pair, one seed, one split, one union
shape. The `shared` arm is a single run and was not replicated.

**Non-claims of reading 2, which travel with it.** The tag's effect is
**unproven, not proven harmful** â at n=150 this control cannot resolve an
effect smaller than roughly Â±0.06 (veto) to Â±0.12 (perm). One model, one
corpus pair, one seed, one split. The _capability_ half of the Part 2
reading is unaffected and strengthened: one adapter over two disjoint-label
tasks beats the matched trivial baseline by +0.27 (perm) and +0.50 (veto),
with no unconditional prior (K'-G5 passes).

## Correction to the 5-hour budget (C-12)

The budget table above prices **J'-A** at 45-60 min. Measured, the native
marginal-cost arm is **~53 s on a quiet box and 4 m 47 s on a saturated
one** (19.5 s of CPU in 287 s of wall â 93 % of the wait was GPU/IO behind
qemu, dartvm and three `rustc`). The hour in the budget was for the
_reasoning_, not the machine.

The budget's own arithmetic was also off: the K'-B arm was priced at 60-90
min and the arms actually train in **~17-18 min each** (cond 1084 s,
untagged 995 s). With the TIER 0 / TIER 1 split (train and cache the
completions once; answer every gate question from the cache in ~6 s on CPU),
the _scoring_ half of this lane is no longer GPU-bound at all.

**The operational rule this implies, and the reason it is written here:** GPU
arms are serial (two concurrent GPU jobs halve throughput), so the budget
that matters is the **sum of training arms**, not the number of questions
asked. Ask more questions of the cached completions; spend GPU time only on
arms that need a _new model_.

## Corrections carried by Part 3

| #    | The record says                                                                                                                                                       | The verified finding                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Evidence                                                                                                                                                                                                                                                                |
| ---- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| C-11 | K'-G1..K'-G6 define the K' gates; reading 1 states "selectivity IS recoverable by conditioning"                                                                       | **The gates never contrasted the gate arm with its control**, so reading 1 was unfalsifiable as encoded. The control (`untagged`) is at least as good as `cond` on both tasks; the tag's paired effect is not significant.                                                                                                                                                                                                                                                                                                                                                                                                                                                                | `MTP-GATES.md` Parts 1-2 (0 occurrences of `untagged`/`permsolo`/`control`); `adapter_conditioning.py:649`; `RESULTS-adapter-conditioning-2026-10-21.md`                                                                                                                |
| C-12 | the 5-hour budget prices J'-A at 45-60 min and K'-B at 60-90 min                                                                                                      | The native arm is ~53 s quiet / 4 m 47 s contended; the K' arms train in ~17-18 min. The budget conflated reasoning time with machine time.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | `qwen_marginal_cost` runs (2026-10-21); the K' run's own timings                                                                                                                                                                                                        |
| C-13 | C-10: "the Rust surface **cannot load that artifact at all** — `mlx_lm` writes `lora_a`/`lora_b`, the Rust loader accepted only PEFT `lora_A.weight`/`lora_B.weight`" | **The loader half was closed; the PRODUCTION PATH was not.** `LoraAdapter::load_mlx_lm` existed with **zero call sites**: `NurseryModel::load_with_adapter` still called the PEFT-only loader, and the parity test that would prove the bridge was `#[ignore]`d. **Now closed**: `LoraAdapter::load_auto` DETECTS the layout from the tensor names and REFUSES a file in neither (or both); `load_with_adapter` calls it; the two parity tests run (the `#[ignore]` was hiding a defect — the lib test binary created a Metal stream before the kernel library was pinned, and MLX aborted in `default_stream`); and a new gate loads and merges the artifact this lane actually trained. | `src/lora.rs` (`load_auto`, `detect_format_from_names`, the two un-ignored tests); `src/nursery_model.rs:376`; `src/lib.rs` (`pin_metallib_colocated`, now called from `mlx::gpu()`); `tests/mlx_lm_artifact_merge.rs` — 27 lib + 8 swap + 1 artifact test pass, 0 fail |

---

# PART 4 — the acceleration program and the two closing controls (frozen 2026-10-21, BEFORE any of these arms runs)

Parts 1–3 decided the experiment line. The attribution is settled: the
multi-task training data is load-bearing, the `Task:` tag is not (paired
p = 0.185 / 1.000), and the option list naming the task is not the mechanism
(`shared` still transfers) but is worth ~7–9 points and prevents a 6 %
foreign-label leak. MTP (Line J) is closed on physics.

Part 4 freezes the gates for what comes next — the **acceleration program**
and the two controls that can close the LoRA line on their own. It is frozen
**before any of these arms runs**, by the same law as Parts 1–4: a threshold
written after seeing data is a knob. No arm below has run. No
threshold here may move after one does.

> **Post-run status (2026-10-26, final: every gate in this Part has run).**
> Since this Part was frozen: **L-G1 (few-shot) and L-G6 (ranking) ran and
> FAILED on both tasks**, **L-G3 is satisfied** (every cell re-scored at
> coverage 1.0000), **L-G2 (noise adapter) ran and MISSED on both tasks**
> (0.5392 vs a 0.7737 threshold; 0.2511 vs 0.6533 — the gain is not explained
> by format alone), and **L-G7 (third task) ran and PASSED** (shared 1.0000 =
> untagged 1.0000 on the dissimilar pair, leak 0, completions 204/204
> identical; the pre-registered first case fires: per-task by default, shared
> defensible across a semantically dissimilar group). The LoRA line is
> CONFIRMED load-bearing with the format explanation measured out and the
> shared-answer-space rule measured at both ends. L-G4 measured (lever real,
> fused forward absent); L-G5 remains a bench. Evidence:
> `bench/nursery/experiments/RESULTS-noise-2026-10-26.md` and
> `RESULTS-third-2026-10-26.md`; ledger: [`LINES.md`](LINES.md) Row M;
> classification and what is next: [`VERDICTS.md`](VERDICTS.md). No threshold
> below has moved.

Line naming: **Line L** = the acceleration program. Its ledger row is
**Row M** in [`LINES.md`](LINES.md); its cost and order are in
[`EXPERIMENT-PLAN.md`](EXPERIMENT-PLAN.md) Part B.

## The reference number these gates are measured against

`untagged` is the reference, not `cond`. Part 3 established that the tag is
not load-bearing, so every comparison below uses the **untagged adapter's
strict-match accuracy** (perm 0.8733, veto 0.7800, over the 150 scored rows)
as the number a no-training path has to approach. A gate that compared against
`cond` would be comparing against the worse of two equivalent arms.

## The DeepInfer transfer (reviewed from source, recorded here so it is not re-read as evidence)

An external inference engine's patterns were reviewed from its source. The
honest verdict is that the review changes the **NUMBER**, not the **VERDICT**,
on shared-versus-separate, and it reopens nothing in this lane. Two ideas have
a stake here; the rest do not.

- **Batch invariance — the one idea with a MECHANICAL stake.** A batched
  decode whose output depends on a sequence's position in the batch would
  silently make every number measured through that path a function of the
  batch size, and the batch size is a choice. Batch invariance is therefore a
  **precondition of L-G4**, not a detail of it: L-G4's ratio is not a
  measurement until the decode is shown to be invariant, or its divergence is
  measured and reported beside the ratio.
- **Prompt-shape / prefix-cache uniformity — the one idea with a PRODUCT
  stake.** A shared answer space is one instruction prefix, so it is cacheable
  across tasks. That is exactly what **L-G5** measures (prompt bytes, prefill
  wall, prefix-cache hit rate), and it is a cost question, not an accuracy one.
- **DeepInfer's MTP does not reopen this lane's.** Its draft head is
  **pretrained** (a DeepSeek-V4.1 checkpoint), not trained from scratch, and
  its hardware is SM100 / Ascend 950 — a different machine class from the M1
  this lane measures on. `USE_NEXTN_DECODE=5` is a **maximum**, not evidence
  that count 5 works. Do not read DeepInfer as evidence for or against any
  verdict here, and do not read it as reopening Line J (closed on physics:
  `body(8)/body(1)` = 2.0–3.5 against a 1.50 NOT-FLAT gate).

## L-G1 — the few-shot control

**Question.** Is the LoRA line a prompt-format workaround? That is: does the
base model, given eight exemplars and no training, already reach what the
adapter reaches?

**Threshold.** `fewshot(base, 8 exemplars)` accuracy ≥ the `untagged` adapter
accuracy − 0.05, on **BOTH** tasks, strict-match, over the same scored rows.

**Pre-registered failure reading.**

- **PASS** (few-shot clears `untagged − 0.05` on both tasks) ⇒ the line is a
  prompt-format workaround. **No further training arms are bought**: not the
  noise adapter, not the third task. The lane closes, and the product question
  becomes "prompting versus training", not "adapter".
- **FAIL** (few-shot misses on either task) ⇒ the adapter contributes beyond
  exemplars at this budget, and the line continues.

The direction is deliberate and easy to misread: here a **PASS closes the
training line** and a **FAIL keeps it open**. A reader who treats PASS as "the
adapter wins" reads this gate backwards.

**Non-claim.** A FAIL does not prove the adapter is necessary. The corpus is
small and the exemplars are few (eight); it only means exemplars at this
budget did not match the adapter. It says nothing about a larger exemplar
budget, and it is not a product decision on its own.

## L-G2 — the noise-adapter control

**Question.** How much of the gain is "emit a legal label" rather than "learn
the decision"?

**The control.** The `noise` adapter is trained on the **same corpus with the
labels randomized**, so it has seen every legal label and none of the mapping.
It is the control for the format explanation; the gate arm is `untagged`.

**Threshold.** The `noise` adapter reaches within 0.10 of `untagged` on a
task — pinned, so "within" cannot be read two ways: `noise ≥ untagged − 0.10`
on **either** task (strict-match, same scored rows).

**Pre-registered failure reading.**

- **HIT** (`noise ≥ untagged − 0.10` on either task) ⇒ the capability is a
  **FORMAT** capability: an adapter that learned no mapping scores nearly as
  well as one that learned the decision. The product must not claim decision
  capability, and the noise arm becomes the **mandatory floor** every future
  arm is measured against.
- **MISS** (`noise < untagged − 0.10` on both tasks) ⇒ the gain is not
  explained by format alone.

**Non-claim.** A MISS does not isolate the mechanism. It only excludes the
pure-format explanation. It does not say what the adapter learned, and it does
not license a decision-capability claim on its own.

## L-G3 — coverage completeness

**This gate has no pass/fail. It is a definition, and a violation invalidates
the reading it was applied to.**

Every gate number in this file is computed over **ALL rows of the scored
split**, not a prefix. Coverage = `scored_rows / corpus_rows`, and it is
**printed beside every number**. A number with coverage < 1.0 is labelled
`partial` and is **not a gate input**: it cannot pass, fail, hit, or miss a
gate, and it cannot move a threshold.

**Why this is a gate and not a convention.** The lane measured a capability
delta of **+0.2603** against a matched **+0.2733** on the same arm — a 0.013
gap with no model difference behind it — because the trivial baseline was
computed over the corpus's **293** perm rows
(`baselines.perm.n = 293`, strongest trivial 0.5597) while the scoring covered
the first **150**. A threshold read against the wrong sample set is a threshold
read against a different experiment. The matched baseline, taken from the
cache's own gold over the scored rows, is the only baseline a gate number may
cite.

## L-G4 — the batched-decode lever

**Question.** Can this device decode more tokens per second by running N
sequences at once?

**Measurement.** Aggregate tok/s at concurrency 1, 2, 4, 8 and 16, on the
**same prompt set**, forced-eval (MLX is lazy: a dummy eval measures graph
construction, and this lane has a measured **28.7×** error from exactly that),
interleaved so thermal drift cancels rather than biasing the ratio. The power
state and the real charge current are printed beside every number.

**Precondition (batch invariance).** Before any ratio from this measurement is
quoted, the decode must be shown to be **batch-invariant**: the same sequence
must produce the same output regardless of its position in the batch and
regardless of the batch size. If it does not, the divergence is measured and
reported, and **no number measured through that path is a gate input** — it is
a function of a choice (the batch size), and a function of a choice is not a
measurement. This is the mechanical stake of the DeepInfer review, and it is
encoded here rather than left as a note.

**Threshold.** The aggregate ratio at concurrency 8 — `tok/s(concurrency 8) /
tok/s(concurrency 1)`, same prompt set — **≥ 1.5** ⇒ batching IS a lever on
this device, and the acceleration program rests on it. **< 1.5** ⇒ batching is
NOT a lever on this device; the acceleration program rests on train-once /
reuse plus replay, and **no further batching work is bought**.

**Pre-registered failure reading.** A miss here (`< 1.5`) is a device fact, not
an implementation gap to be tuned: it closes the batching lane the way J'-G0's
NOT-FLAT closed the MTP lane. No second batching arm is bought to push the
ratio over the line.

**Non-claim.** ONE model, ONE device, under whatever power state was recorded
beside the number. The **ratio** is the measurement. Absolute tok/s is not a
claim and is not comparable across runs (the same prebuilt binary took 53 s on
a quiet box and 4 m 47 s on a loaded one).

**Post-run note (2026-10-21, AFTER the bench ran). The THRESHOLD and the
FAILURE READING above are UNCHANGED — this note clarifies the PRECONDITION,
which the bench turned out to be measurable in two different senses.**

The bench measured a **bit-level** divergence: on the real quantized weights,
a batched matmul is not bit-identical to the same row alone (max abs diff
0.0625 in the body GEMM, 0.0239 in the tied projection), and the
**same-shape-class control diverges too** — so the `gemv`→`skinny_gemm`
kernel switch is not the explanation; the batch dimension is.

**Bit-identity is not available on a low-precision trunk, and it was never the
right bar.** The product's own engine already carries the same contract, in
the same spirit as DeepInfer's `DEEPINFER_BATCH_INVARIANT`, and it already
settled the bar question (`test/laya_native_batch_isolation_test.dart`): the
**DECISION** a question resolves to is compared **exactly** (`==`) — "a
different answer is a different answer, never a rounding difference" — and
the **distribution** to a **1e-3** tolerance. That tolerance is not
arbitrary: on this machine, against the fp16 laya-mlx checkpoint, a **pure
batch-SIZE change** (the same row, repeated) moved a probability by **at most
3.6e-4** — the float16 re-rounding floor — while a real heterogeneous-batch
defect moved one by **0.86**. The tolerance admits the floor with ~3× headroom
and **rejects the defect by three orders of magnitude**. That test's own
comment: _1e-6/1e-5 are NOT defensible: they assume the native logits are
bit-identical across batch shapes, which a float16 trunk cannot deliver._

**So the precondition is REFORMULATED, not waived.** A fused batch must show:

1. **decision-level invariance** — the LABEL (this lane's gate input) and the
   engine's categorical decision must not move with the batch size, at a
   stated tolerance; **and**
2. **no short-row defect** on the heterogeneous (left-padded) path — a
   _measured_ hazard on this stack, not a hypothetical one, and exactly the
   path a fused batch must take for unequal prompt lengths.

Until both hold, no number measured through a fused batch is a gate input. The
measured bit-level floor is reported beside every fused number, not discovered
by a reader. Evidence:
`bench/nursery/experiments/RESULTS-acceleration-2026-10-21.md` §1.5–1.6.

## L-G5 — the prompt-shape cost

**Question.** What does the answer space cost per request?

**Measurement.** The per-task option list against the shared union list:
prompt bytes, prefill wall, peak KV bytes, and prefix-cache hit rate, at
concurrency 1 and at concurrency 8. This is the product stake of the DeepInfer
review — a shared answer space is one instruction prefix, so it is cacheable
across tasks — measured rather than assumed.

**Threshold.** A shared answer space is product-legal only if its penalty is
**≤ 10 %** of the per-task prefill wall **AND** it adds **0 prompt bytes per
request** beyond the shared prefix. Otherwise the per-task list is free and
the shared list is not.

**Pre-registered failure reading.** A shared list that adds per-request bytes,
or that costs more than 10 % of the per-task prefill wall, is not product-legal
on cost grounds — whatever L-G7 says about its accuracy. The two gates are
independent: a shared list can be accurate and still be illegal here, and
legal here and still leak under L-G7.

**Non-claim.** This is a **COST** gate, not an accuracy gate. Accuracy is
L-G7's business. A pass here says nothing about whether the shared list answers
correctly.

> **Post-run status (2026-10-26): FAIL at these frozen terms, with the
> penalty measured as fully recoverable at one product shape.** The shared
> union list adds +22 tokens (+96 B) per request and +55 % cold prefill
> wall (c=1 AND c=8, fused-batched) — both clauses fail. At a
> product-shaped window (2048+ shared instruction tokens, two tasks
> interleaved) a warm prefix pool serves the shared list at 100 % hit rate
> (2168/2169 matched) and 32–43 ms per request vs ~1880 ms cold — a 57×
> prefill reduction — while the per-task lists hit 0 % on every task
> switch. Per-task remains the default; shared is legal only where a long
> shared prefix is actually cacheable. Evidence:
> `bench/nursery/experiments/RESULTS-fused-tier-a-2026-10-26.md`. No
> threshold above has moved.

## L-G6 — ranking versus generation

**Question.** Can the legal labels be RANKED instead of generated?

**Measurement.** Ranking accuracy — argmax over the legal labels'
log-probabilities, length-normalized — against the generation-plus-strict-match
accuracy, on the **SAME items**.

**Threshold.** `ranked(base)` ≥ the `untagged` adapter accuracy − 0.05, on
**BOTH** tasks.

**Pre-registered failure reading.**

- **PASS** (`ranked(base)` clears `untagged − 0.05` on both tasks) ⇒ **the
  LoRA line is not bought.** A base model with constrained ranking delivers the
  same capability with zero training. No training arm — noise, third task, or
  otherwise — is bought on the strength of this lane.
- **FAIL** (`ranked(base)` misses on either task) ⇒ generation, and therefore
  the adapter, is load-bearing.

As with L-G1, a **PASS closes the line** and a **FAIL keeps it open**. Both
gates exist because each can end the program on its own, which is why both run
before any training arm.

**Non-claim.** A PASS is not a product decision. It is evidence that a
zero-training path exists, which then has to be costed (L-G4, L-G5) and
productionised before it is a product.

> **Post-run status (2026-10-26, corrected scorer).** The native
> implementation's recorded numbers were produced with a broken scorer
> (the stable logsumexp's missing max add-back, and a probability-vs-
> logprob comparison in the eos diagnostic). Both fixed; the corrected
> native run agrees with the python scorer EXACTLY on perm (0.4403 ==
> 0.4403 == generation) and reads veto 0.3128 mean vs python 0.2291 — a
> residual recorded in
> `bench/nursery/experiments/RESULTS-tier-c-repairs-2026-10-26.md`. **The
> FAIL verdict above is unchanged and strengthened** (every corrected
> number is far below the frozen thresholds); the threshold did not move.

## L-G7 — the third, dissimilar task

**Question.** Does the shared-answer-space rule hold when the tasks are
semantically distant?

**The arm.** A third task with a **disjoint** label set, majority class
**< 0.5**, every label represented — the same non-degeneracy bar K'-G3 set.
Perm and veto are both permission requests, so the pair measured so far is the
semantically _close_ end; this task is the distant end.

**Threshold.** The `shared` arm loses **≤ 0.05** to `untagged` on the third
task (`shared ≥ untagged − 0.05`) **AND** the foreign-label leak is **0**.

**Pre-registered failure reading.** Three cases, all pre-registered — a gate
with an open middle case is a gate that gets read whichever way the result
points.

- **Both hold** (`shared ≥ untagged − 0.05` and leak = 0) ⇒ a shared answer
  space is legal for a semantically dissimilar group. The per-task default
  stands (it is cheaper, see L-G5), but the shared option is no longer
  excluded, and the rule becomes: **per-task by default; shared is defensible
  across a semantically dissimilar group.**
- **The leak is 0 but the loss is > 0.05** ⇒ the shared list does not leak and
  is still not free: the option list is worth ~7–9 points of _vocabulary_, and
  the per-task default is confirmed. The shared space is merely unnecessary,
  not broken.
- **The leak is > 0** ⇒ the shared answer space is **not legal on the distant
  pair either**, and the per-task default is confirmed for every pair measured.
  **This falsifies the upper-bound reading below**, rather than supporting it:
  a leak on a semantically DISSIMILAR task is not evidence that closeness
  caused the leak, it is evidence that the leak is not a closeness artifact at
  all. The rule tightens to: **per-task answer spaces, always, until a pair
  that does not leak is measured.**

**Non-claim.** Perm and veto are both permission requests, so the 6 % leak
measured on that pair (9/150 veto answers emitted the perm label `abstain` on
gold `no_grant`) is an **upper bound** — _unless_ the third task leaks, in
which case the upper-bound reading is void and the leak is unbounded by
semantic closeness. The third task establishes the lower end of the leak, not
a population rate. Nothing here is a rate for an arbitrary task pair.

## What a pass and a miss buy (so the order is visible from the gates)

L-G1 and L-G6 are the closing gates: **either passing, on its own, ends the
LoRA line and buys no further training.** They are inference-only, so they run
first. L-G2 (the noise adapter) and L-G7 (the third task) are training arms,
and they are conditional — a line that L-G1 or L-G6 already closed does not
need them. L-G4 and L-G5 are cost gates: they decide what the acceleration
program rests on, and they decide nothing about whether the adapter is worth
training. The cost, the arms, and the pre-registered order are in
[`EXPERIMENT-PLAN.md`](EXPERIMENT-PLAN.md) Part B.

## The DeepInfer draft-head architecture (observation, recorded 2026-10-21; reopens nothing)

The DeepInfer transfer section above records that DeepInfer's MTP does not
reopen this lane. It does not record the **architecture** of DeepInfer's draft
head, and that architecture is relevant to how a future arm would have to be
**shaped**. The four differences below are observations about a foreign
codebase, read from its source; they are not measurements of ours, not
thresholds, and not evidence for any verdict above.

**What this does NOT change.** Line J stays closed on physics. The gates
above — J-G1..J-G5, K-G1..K-G4, K'-G1..K'-G3, L-G1..L-G7 — are unchanged.
This section is evidence **for a future arm's shape**, not a threshold and not
a reopening. Nothing here is a gate, and no threshold may be moved by it.

1. **Draft init is a NOISE token, not the previous proposal.** In
   `deepinfer/model_executor/models/mtp/dflash.py`, `_embed_draft_init_tokens`
   fills the draft rows with `noise_token_id`
   (`cfg.dflash_cfg.dspark_noise_token_id`) and only position 0 receives the
   golden token. This structurally avoids the failure our Line J measured (a
   wrong previous proposal poisoning the next step). **LIMIT:** their head is
   pretrained; the init trick is an architectural idea we have not tested, and
   it does not by itself make acceptance high.

2. **The previous token enters as a LOW-RANK MARKOV EMBEDDING, not raw token
   identity.** `markov_w1` (a `VocabParallelEmbedding` over the vocabulary) and
   `markov_w2` (a `ReplicatedLinear` to the vocabulary, `use_fp32_output=True`),
   with rank `cfg.dflash_cfg.dspark_markov_rank`. **LIMIT:** unmeasured here; a
   low-rank embedding of the previous token is a different inductive bias from
   our depth-collapse mechanism and would need its own arm.

3. **A ConfidenceHead predicts per-step acceptance, and the scheduler
   allocates draft budget DYNAMICALLY per request.** In
   `deepinfer/model_executor/models/mtp/dflash.py`, `ConfidenceHead` projects
   `n_embed + markov_rank` to 1 with a per-step temperature
   (`DEEPINFER_DFLASH_CONFIDENCE_HEAD_TEMPERATURE`, a comma-separated list
   whose length must equal `DEEPINFER_USE_NEXTN_DECODE`). In
   `csrc/engine/mtp_varlen.hpp`, `MTPVarlen::schedule` sorts requests by
   predicted acceptance descending, greedily allocates draft slots, and picks
   the total batch size maximizing expected throughput — i.e. it is **NOT** a
   fixed count K. **LIMIT:** DeepInfer's head is pretrained on a much larger
   trunk; a from-scratch confidence head on a 0.6B trunk is a different
   experiment, and this is a per-request **budget policy**, not a per-prompt
   accuracy fix.

4. **The head reads MULTI-LAYER target-layer features, not only the last
   hidden state.** `cfg.dflash_cfg.dspark_target_layer_ids` selects the target
   layers; `DFlash.projection` maps `hidden_size * num_target_feature_layers`
   to `hidden_size`. **LIMIT:** our trunk's layer set and feature widths
   differ; "read more layers" is a hypothesis, not a measured gain.

**The one measured claim that touches this.** Our own measured numbers
(acceptance 0.1393 / 0.0146 / 0.0000 by depth, and the 0.124 decode-consistent
arm-C figure) are from
`bench/nursery/experiments/RESULTS-mtp-2026-10-21.md` and are **not** changed
by anything in this section. Any future arm that uses a noise init, a markov
embedding, a confidence head, or multi-layer features must be **REGISTERED as
a new arm with its own frozen threshold BEFORE it runs**, exactly as Parts 1–4
did — a threshold written after seeing data is a knob.
