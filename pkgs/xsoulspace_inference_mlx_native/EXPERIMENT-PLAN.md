# EXPERIMENT-PLAN â the MTP/LoRA lane's next arms, sized to run in parallel

**This file is the analysis + the parallelization plan for the arms named in
[`MTP-GATES.md`](MTP-GATES.md) PART 2.** It does not change any gate, any
threshold, or any pre-registered reading. Where it disagrees with the frozen
record it says so and shows the evidence; the gates file stays frozen and this
file is the correction of RECORD, not of contract.

Read it with: [`LINES.md`](LINES.md) (the tracked verdict ledger) â
[`MTP-GATES.md`](MTP-GATES.md) (the frozen gates) â this file (what is next,
and what it costs).

---

> ## STATUS (2026-10-21, later session) â all four lanes are DONE
>
> Do not re-run any arm below; the results are in the tracked files.
>
> | lane                                 | outcome                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | where it landed                                                                                                          |
> | ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
> | **A â the disjoint-option-list arm** | **DONE.** The arm ran (`shared`: both tasks, no tag, ONE option list for both). It **still transfers** (+0.240 perm, +0.440 veto over the matched trivial baseline), so the pre-registered "it works â the mechanism is the input text" branch fires: the option list is a _refinement_ (~7â9 points), not the mechanism. The nine out-of-set answers in shared/veto are **all `abstain`** on items whose gold is `no_grant` â the same decision in the wrong family's vocabulary.           | `RESULTS-adapter-conditioning-2026-10-21.md` Â§2b; `MTP-GATES.md` K''-G2; `LINES.md` Row K                                |
> | **B â the audit + the record**       | **DONE.** The replay answers every gate question from the cached completions (10 cells, ~1 s, no GPU) and writes `adapter-conditioning-replay.json` + a sha256 manifest. The record is written: the RESULTS file, `LINES.md` Row K, `MTP-GATES.md` Part 3 (C-11/C-12/C-13, K''-G1, K''-G2), and four META-LESSONS.                                                                                                                                                                           | `bench/nursery/experiments/adapter-conditioning-2026-10-21/`                                                             |
> | **C â Arm E's three items**          | **DONE.** (1) `LoraAdapter::load_auto` DETECTS the on-disk layout and REFUSES a file in neither (or both); `NurseryModel::load_with_adapter` calls it. (2) The two format-parity tests are un-`#[ignore]`d and pass â the ignore was hiding a real defect (a Metal stream created before the kernel library was pinned), fixed by pinning inside `mlx::gpu()`. (3) A new gate loads and merges the artifact this lane actually trained. **27 lib + 8 swap + 1 artifact tests pass, 0 fail.** | `src/lora.rs`, `src/nursery_model.rs`, `src/lib.rs`, `src/mlx.rs`, `tests/mlx_lm_artifact_merge.rs`; `MTP-GATES.md` C-13 |
> | **D â the durable ledger**           | **DONE.** The RESULTS file Row K' pointed at now EXISTS; the J'-A ratio band is corrected to **2.0â3.5** (three runs: 2.8â3.5, 2.428, 2.034), and the wall clock is marked as a non-claim (53 s quiet / 4 m 47 s contended on the same prebuilt binary).                                                                                                                                                                                                                                     | `LINES.md` Rows J and K                                                                                                  |
>
> **What is left is a PRODUCT question, not a mechanism question.** The
> mechanism is settled: the multi-task training data is load-bearing, the
> `Task:` tag is not, and the option list does not have to name the task.
> Open: (a) ship a task-specific option list (~8 points better) or a shared
> one (simpler prompt, same decisions); (b) the live prefix cache still does
> not CONSUME the adapter-digest key — it is keyable, not invalidated; (c) the
> 4-bit base is still refused at bind, which is correct, so a shipping path
> needs an f32 base or a merge policy.
>
> ## STATUS (2026-10-21, evening) — the experiment line is DECIDED; next is the acceleration program
>
> The table above stands; nothing in it is re-opened. Since it was written the
> two open mechanism questions closed, and the next work changed kind.
>
> **Decided.** The attribution and the product shape are settled
> ([`LINES.md`](LINES.md) Row K, [`MTP-GATES.md`](MTP-GATES.md) Part 3):
> one adapter trained on all tasks, untagged, prompted with an answer space.
> The multi-task data is load-bearing; the `Task:` tag is not (paired
> p = 0.185 / 1.000); the option list naming the task is not the mechanism
> (`shared` still transfers) but is worth ~7–9 points and prevents a 6 %
> foreign-label leak. Of the three items left open above: (b) closed — the
> engine now owns its weight identity and the pool drops entries computed under
> other weights ([`LINES.md`](LINES.md) Row L); (c) stands as correct, not as a
> gap; (a) is no longer a guess — it is **L-G5** (the cost) and **L-G7** (the
> accuracy), frozen in [`MTP-GATES.md`](MTP-GATES.md) Part 4 before either runs.
>
> **Next.** Not another mechanism arm. The acceleration program: six arms, four
> of them inference-only, two of them able to close the LoRA line on their own.
> The gates are L-G1..L-G7 (frozen before any of them runs); the cost, the arms
> and the pre-registered order are Part B below. The ledger row is **Row M —
> the acceleration program** in [`LINES.md`](LINES.md).
>
> **Post-run status (2026-10-26, final: every Part-B gate has run).** L-G1
> and L-G6 ran and FAILED on both tasks (the LoRA line is CONFIRMED, not
> closed — a PASS would have ended it); L-G4's amortization probe ran (the
> lever is worth buying at a projected 5.39× @ batch 8, but the fused forward
> does not exist); L-G3 is satisfied (coverage 1.0000 on every cell); L-G2
> ran and MISSED on both tasks (0.5392/0.2511 vs thresholds 0.7737/0.6533 —
> the format explanation is measured out; ≈ 7 min training on AC); **L-G7
> ran and PASSED** on the dissimilar pair perm+third (shared 1.0000 =
> untagged 1.0000 on the third cell, leak 0, completions 204/204 identical —
> per-task by default, shared defensible across a semantically dissimilar
> group; the shared list still cost −0.089 on the same run's perm cell).
> L-G5 remains a bench. What is next is engineering, not gating: the fused
> batch (Tier A in [`VERDICTS.md`](VERDICTS.md)), the L-G5 cost bench, and
> the Tier-C record repairs. Evidence:
> `bench/nursery/experiments/RESULTS-noise-2026-10-26.md` and
> `RESULTS-third-2026-10-26.md`; ledger: [`LINES.md`](LINES.md) Row M.
>
> ## STATUS (2026-10-27) — the engineering landed; the closed set is extracted
>
> Tier A is BUILT, GATED, and MEASURED (fused batch 1.93× @ B8 / 3.19× @ B16,
> the 5.39× projection retired); three of the four Tier-C repairs closed
> (arm determinism measured, seed E2E pinned, L-G6 localized to two real
> native-scorer bugs — both fixed, engines now agree exactly on perm). The
> fourth — the native-surface capability number — landed the same day via
> `Qwen3::attach_lora` (runtime LoRA on the 4-bit base, the no-confound
> option), together with Tier B-5, ranked(adapter). Readings and frozen
> bars: `bench/nursery/experiments/RESULTS-native-surface-2026-10-27.md`.
> **The closed-experiment register and the live open list now live in
> [`ROADMAP.md`](ROADMAP.md)**; the remaining open items are the veto
> residual cross-read (a gate input once ranking is), the product wiring of
> the fused batch, RUNG-1 (PERM-GATE-1), and a CI gate.

---

## 1. Where the lane actually stands (verified 2026-10-21 ~17:45)

| Line                                 | State                                                                                                                                                                         | Evidence                                                                                                                              |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| **J â MTP as speed**                 | **CLOSED on physics.** J'-G0 already fired: NOT FLAT.                                                                                                                         | `qwen_marginal_cost` â `body(8)/body(1) = 2.428` (this session), recorded 2.8â3.5 across runs. The gate's NOT-FLAT threshold is 1.50. |
| **K â swappable adapter set**        | **Mechanical surface proven; the SET is not justified.** The 2026-10-21 capability number did not survive re-measurement (C-4, C-10).                                         | `LINES.md` Row K.                                                                                                                     |
| **K' â the conditioning re-ask**     | **COMPLETE (17:55).** All three arms trained and scored. The pre-registered reading fires on the numbers; the control arms show the reading's _conclusion_ is wrong (see Â§4). | `bench/nursery/experiments/adapter-conditioning-2026-10-21.json`; replay in `adapter-conditioning-replay.json`.                       |
| **L â prefix-cache weight identity** | **LANDED (code).** The engine owns its weight identity; the pool drops any entry computed under other weights.                                                                | `qwen.rs::weight_identity`, `qwen_prefix.rs`, test `a_weight_change_drops_every_entry`.                                               |

### 1.0 The completed K' run, in one table (matched baselines)

Replay from the cached completions via `fast_score.py` (2.09 s, 8 cells, no GPU):

| arm                      | trained on | tagged  | perm       | veto       |
| ------------------------ | ---------- | ------- | ---------- | ---------- |
| base                     | â          | â       | 0.4533     | 0.2400     |
| trivial (matched, n=150) | â          | â       | 0.5467     | 0.2733     |
| **cond**                 | both tasks | **yes** | 0.8200     | 0.7733     |
| **untagged**             | both tasks | **no**  | **0.8733** | **0.7800** |
| **permsolo**             | perm only  | no      | **0.9600** | **0.1733** |

Three things fall out of this table, and only one of them is what the frozen
reading expected:

1. **Capability survives the strict scorer, and grows.** `cond` beats the
   trivial baseline by **+0.273 (perm)** and **+0.500 (veto)** â far above
   the disputed 2026-10-21 +0.153. The K'-G1 capability claim is _retained_,
   on a strict scorer, on a non-degenerate second task.
2. **The `untagged` control beats the tagged arm** on both tasks
   (â0.053 perm, â0.007 veto for `cond`). Paired McNemar over the same
   items: perm p = 0.185 (not significant), veto p = 1.000 (not significant).
   **The tag is not load-bearing** â and the untagged prompt still names the
   task through its option list, so the arm was never "untagged" in the sense
   the reading assumes.
3. **`permsolo` reproduces the interference, decisively and in the right
   direction.** A perm-only adapter reaches 0.9600 on perm (the best cell in
   the run) and **collapses to 0.1733 on veto â _below_ the 0.2733 trivial
   baseline (â0.1000)**. Paired McNemar vs `cond` on veto: 102 discordant
   items, p < 0.0001. This is the 2026-10-21 "â0.847" interference, now
   reproduced at a **smaller magnitude on a non-degenerate task with a strict
   scorer**, and it confirms the mechanism: interference comes from the
   adapter's **unconditional prior**, not from the scorer.

So the honest reading is _not_ the frozen one. The frozen reading says
"selectivity is recoverable **by conditioning**". The data says: selectivity
is recoverable by **multi-task training on disjoint label sets**, and the
`Task:` tag is **not** the active ingredient â the prompt's option list
(which differs per task) is. And the interference that killed the 2026-10-21
set is real, is reproduced, and is _avoided_ by training one adapter on both
tasks â but the evidence says that avoidance comes from the multi-task
training data, not from the tag.

### 1.1 J'-G0 already fired, and it fired in 53 seconds

`MTP-GATES.md` budgets J'-A at **45â60 min**. The measured wall clock of
`cargo run --release --bin qwen_marginal_cost --positions 1,2,4,8 --reps 3`
is **53 s**. The arm is not expensive; the _budget_ was wrong. The verdict:

```
body(8)/body(1) = 2.428   ->  NOT FLAT  ->  MTP-as-speed is closed on physics
                             for ANY acceptance  ->  no MTP arm is bought
```

This is the single most important fact for planning: **Line J needs no further
GPU time.** The marginal-cost arm is already a sub-minute arm. Re-running it
is a _confirmation_ (< 1 min), not a _discovery_.

### 1.2 The bigram baseline independently reproduced

C-2's load-bearing claim is that a trivial bigram beats every arm, which is
what makes the MLP head's shape claim void. Re-derived from
`/tmp/mtp_records_bf16.pkl` (no GPU), split 36 train / 12 held-out greedy
prompts, n = 2292 measured positions:

| baseline | recorded (MTP-GATES C-2) | reproduced                                                                         | verdict                                                                                                                     |
| -------- | ------------------------ | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| bigram   | 0.1483                   | **0.1457** (train pool = greedy-train) / 0.2330 (train pool = corpus+greedy-train) | reproduces; the pool definition decides the value, and **every pool definition lands above the best arm (0.1235 / 0.1243)** |
| copy     | 0.0851                   | 0.0384                                                                             | **does not reproduce** under any pool/eval pair tried (16 combinations swept)                                               |
| constant | 0.0227                   | 0.0515                                                                             | **does not reproduce** under any pool/eval pair tried                                                                       |

The recorded **bigram** number â the one the closure rests on â reproduces.
The recorded **copy** and **constant** numbers do not, and they do not
reproduce under any combination of (pool = greedy-train / corpus / all /
corpus+greedy-train) Ã (eval = held-greedy / held-true / corpus / greedy-all).
They are non-load-bearing for the closure, but they are in the frozen record
and they are wrong. **Correction to record: C-11.**

Note the direction of the copy/constant error: the recorded copy is _higher_
than reality (0.0851 vs 0.0384) and the recorded constant is _lower_
(0.0227 vs 0.0515). Both err in the direction that makes the arms look
_better_ than the trivial baselines â the same direction as the defects C-4
and C-10. The closure still holds because bigram (the strongest trivial
predictor) still beats every arm.

---

## 2. The cost model, measured (this is what makes parallelism possible)

Every number here was measured on this machine during this session, not
estimated. The in-flight K' run is the instrument.

| phase                                                                  | measured wall clock                                                    | where it goes |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------- | ------------- |
| **train one LoRA arm** (400 iters, batch 8, seq 512, 8 layers, rank 8) | **1084 s** (`cond`) / **995 s** (`untagged`) / **1345 s** (`permsolo`) | GPU, serial   |
| **eval one cell** (150 items Ã 64 tokens, one-at-a-time `generate`)    | **~51 s**                                                              | GPU, serial   |
| **score one cell + read the gates**                                    | **0.0 s**                                                              | **CPU only**  |
| **full K'-G1..G6 gate matrix over 8 cells + 4 paired controls**        | **2.09 s**                                                             | **CPU only**  |
| native J'-A marginal-cost arm                                          | **53 s**                                                               | GPU, short    |

The asymmetry is the whole opportunity:

> **Training is 18 minutes. Scoring is 1 second.** Every gate question in
> this lane is a question about a _completion set_, and the completion set is
> already on disk. Re-asking a scoring question does not need the GPU.

### 2.1 The measured wall clock of the in-flight run (pid 76554)

```
16:47  start
16:48  base/perm          (+51 s eval)
16:49  base/veto          (+51 s eval)
17:07  cond trained (1084 s)  -> 17:11 cond/perm  -> 17:16 cond/veto
17:24  untagged trained (995 s) -> 17:34 untagged/perm -> 17:36 untagged/veto
17:55  permsolo trained (1345 s) -> permsolo/perm -> permsolo/veto -> JSON written
```

~20 minutes per arm, of which **18 is training and 2 is evaluation**.

### 2.2 The Rust side, measured

`cargo test --release` (full crate) under load 214â309: **~45 min, dominated by
the compile**, and it **stops at the first failing suite** â the lib suite's
perf gate `l0_ops_run_and_are_dispatch_cheap` failed (1228 us against an
AC-only threshold; the known-flaky gate named in this package's `AGENTS.md`),
so the two lane integration suites **never ran**.

Run directly, they pass, and they are **fast**:

```
tests/lora_set_swap.rs   8 passed; 0 failed   finished in 0.59s
tests/qwen_mtp_parity.rs 3 passed; 0 failed   finished in 0.37s
```

So the lane's own proof is **sub-second** once compiled. The 45 minutes is
`rustc`, not the tests. A targeted `cargo test --release --test <name>` is the
right command for iteration; the full suite is the release gate.

---

## 3. What is already parallel and sub-5-minute â and what is not

### Tier 0 â CPU only, parallel, **< 5 s per cell** (NEW: `tool/nursery/fast_score.py`)

The lane had no CPU-only tier. Every scoring question was priced at the
training cost, which is why the lane kept re-training to answer questions
about scorers. `tool/nursery/fast_score.py` splits the tiers:

- **Tier 0 (GPU):** train the adapter, write the per-item completions. ~18 min, serial.
- **Tier 1 (CPU):** answer _every_ gate question from the cached completions. **1.06 s** for the whole matrix, parallel across cells.

It re-derives, per cell: strict and legacy accuracy, the **item-level
scorer disagreement** (the C-4 defect class, printed with the offending
completions), the **matched trivial baseline** (computed on exactly the rows
that were scored â the run's own baseline is computed over _all_ test rows
while scoring is capped at `eval_limit`, so its "delta vs trivial" mixes two
sample sets: **+0.0131 on perm, +0.0086 on veto** â the new correction
**C-12**), the prediction histogram, top-label concentration (K'-G5), the
outside-label-set count, a **truncation audit** (the cache caps completions at
200 chars, so a re-derived label can disagree with the run's â reported, never
silently absorbed), and a **shadowed-label audit** (which legal labels are
substrings of which, so a scorer defect of the C-4 class is visible before it
becomes a number).

It calls `adapter_conditioning.evaluate_gates` â **the same function the run
uses** â so there is one gate definition, not two. It does not change any
threshold.

### Tier 1 â GPU, short, **~1 min** per arm

`qwen_marginal_cost` (53 s). Re-runnable as a confirmation, on demand, and
cheap enough to run alongside a training job without meaningfully contending.

### Tier 2 â GPU, long, **~18 min** per arm â and NOT parallel

The three LoRA training arms. On this M1 (16 GB, one GPU, shared memory),
training is GPU-serial: two concurrent jobs halve each other's throughput, and
the box is **already at load average 309** with the current run plus a
`cargo test --release` compile plus unrelated Zed/Dart/Android work. This is
the one place where "parallelize the experiments" is the wrong instruction.
**Serial is correct here.**

---

## 4. The finding that changes what to run next: the `untagged` control wins

The `untagged` arm exists to isolate the **tag** from the multi-task training
data (its own docstring says so). The gate function `evaluate_gates` **reads
the `cond` arm only** â `untagged` and `permsolo` are trained, scored, and
then never gate anything. That is a defect in the measurement, and it matters
because the controls contradict the arm they control. The completed run
(Â§1.0) makes it decisive:

**The untagged control beats the tagged arm on both tasks.** The tag is not
load-bearing â it is slightly _harmful_ on perm (â0.0533) and a wash on veto
(â0.0067), and neither difference is significant under a paired McNemar over
the same items (p = 0.185 and p = 1.000).

So the pre-registered reading _"K'-G1+G4 pass, K'-G5+G6 pass â selectivity IS
recoverable by conditioning"_ **fires on the numbers, but its conclusion is
wrong**: the data says selectivity is recoverable **without** conditioning,
from multi-task training on disjoint label sets. That is a _different product
shape_ and a _different claim_ than the frozen reading expects.

Why the untagged arm still works without a tag: **the prompt's option list is
the tag.** The untagged prompt is still
`"Answer with exactly one of: allow_once, abstain"` vs
`"â¦one of: no_grant, destructive_op, outside_workspace, secret_path"` â the
label sets are disjoint, so the option list _names the task_. The arm was
never "untagged" in the sense the reading assumes; it was "tagged by the
option list".

**This is the next arm, and it is cheap.** A third variant â _disjoint option
lists_ (one shared label vocabulary for both tasks, so the prompt carries no
task signal at all) â separates the two remaining explanations:

- if it works â the mechanism is **the input text**, and the label set in the
  prompt is irrelevant;
- if it fails â the mechanism is **the option list** (the prompt naming the
  task), and the honest product is "a prompt that states the answer space",
  not "a task tag".

That arm costs one training run (~18 min) plus two eval cells (~2 min), and
its scoring is **2 seconds** via Tier 0. It is the only GPU arm the lane still
needs.

### 4.1 The `permsolo` cell is the interference reproduction

`permsolo` (perm-only, untagged) is the 2026-10-21 shape, and it does exactly
what that arm's prose claimed â but with a **strict scorer**, on a
**non-degenerate** task, and at a **smaller** magnitude:

| cell       | 2026-10-21 (substring scorer, clause task) | 2026-10-21 K' (strict scorer, veto task)     |
| ---------- | ------------------------------------------ | -------------------------------------------- |
| own task   | â                                          | **0.9600** (vs trivial 0.5467 â **+0.4133**) |
| other task | â0.847                                     | **0.1733** (vs trivial 0.2733 â **â0.1000**) |
| direction  | collapse                                   | **collapse, reproduced**                     |

This closes C-4 properly. The 2026-10-21 record said the interference was a
scoring artifact in _magnitude_; the direction was never in doubt. It is now
confirmed under the strict scorer: a single-task adapter damages the other
task **below the trivial baseline**, on a task with a 0.25 majority, and the
damage is significant (McNemar p < 0.0001). The mechanism is the adapter's
**unconditional prior** â which is exactly what K'-G5 tests and what the
`cond`/`untagged` arms avoid by training on both tasks.

**What is still unknown, and what the next arm settles:** whether the
avoidance is caused by the `Task:` tag or by the option list. The frozen
reading assumes the tag.

---

## 5. Arm E: the format bridge â CLOSED during this session (by concurrent work)

**State as of 18:15:** arm E is closed. This section records the gap and its
closure, because the _gap_ is the instructive part.

### 5.1 The gap, as found (16:52â18:05)

`LoraAdapter::load_mlx_lm` was added to `lora.rs` and it accepts the mlx-lm
format that the training run actually produces â verified against the real
artifact: 112 tensors, 56 Ã `lora_a` / 56 Ã `lora_b`, **0** `lora_A.weight`.
The C-10 gap was closed _at the loader_.

But the production path was still broken:

```
NurseryModel::load_with_adapter  ->  LoraAdapter::load(...)   # PEFT only
mlx_native_nursery_model_load_with_adapter (FFI)  ->  same
LoraAdapter::load_mlx_lm   ->   NO CALLERS
```

`load_mlx_lm` had **zero call sites** outside its own definition, so a real
mlx-lm adapter still could not reach the native engine: the loader that can
read it was not on any path. A loader nobody calls is a loader that does not
exist.

### 5.2 The closure

The production path now goes through `LoraAdapter::load_auto`, which
**detects** the on-disk format from the tensor names and dispatches:

```rust
match detect_format_from_names(...) {
    AdapterFormat::MlxLm => Self::load_mlx_lm(path, scale, s),
    AdapterFormat::Peft  => Self::load(path, scale, s),
}
```

and `NurseryModel::load_with_adapter` calls `load_auto` instead of the
PEFT-only `load`. The contract is the right one: a file in **neither** layout
is **REFUSED**, not read as one of them â the same "refuse, do not
approximate" law K-G4 applies to a quantized base.

A new test, `native/mlx_native/tests/mlx_lm_artifact_merge.rs`
(`the_trained_artifact_loads_and_merges_on_the_native_surface`), exercises
the artifact this run just trained on the native surface. It **skips** when
the artifact is absent â the artifact lives under `bench/`, which is
gitignored â so it is a local gate, not a CI gate, and it says so. Its result
is not claimed here (see Lane C).

### 5.3 What arm E therefore still needs

One thing, and it is the same thing as Â§7: the artifact the test depends on
lives in a gitignored directory, so the gate that proves C-10 is closed
**cannot run on a clone**. The durable fix is to keep a small tracked fixture
of the same on-disk layout (mlx-lm names, the same `[in, r]` / `[r, out]`
orientation) so the bridge is covered without the trainer's output â which is
what a gate is for.

---

## 6. The parallel plan

**Three independent lanes. Only one of them touches the GPU for a long time.**
Run them concurrently; they contend on CPU, not on the GPU's scarce
serial resource.

### Lane A â GPU, serial, ~20 min: the disjoint-option-list arm (the one new experiment)

Single new training arm, per Â§4. Everything else about it is already built
(`fast_score.py` scores it in ~2 s). The K' run it follows has finished, so
the GPU is free â **but** the box is still at load ~90 from unrelated work, so
expect the same ~20 min, not faster.

### Lane B â CPU, parallel, seconds: the audit + the record

Runs _now_, needs no GPU, and produces the two corrections the record needs
(C-11 copy/constant baselines, C-12 baseline sample-set mismatch), plus the
control-arm comparison Â§4 that the frozen `evaluate_gates` does not read.

```
python tool/nursery/fast_score.py   --completions /tmp/adapter_conditioning/completions   --jobs 8 --audit --out bench/nursery/experiments/adapter-conditioning-replay.json
```

**Done this session:** the replay was run, all 8 cells reproduce the run's own
numbers to 1e-9, and `adapter-conditioning-replay.json` is written. What
remains in this lane is the _record_ (Lane B2 below).

### Lane B2 â CPU, minutes: the record, which is the actual gap

`bench/` is gitignored, so the lane's spine is currently invisible to a clone.
The durable fix is **not** more artifacts â it is three tracked files:

1. `RESULTS-adapter-conditioning-2026-10-21.md` â the K' results with the
   Â§1.0 reading, written so that a reader lands on the _corrected_ story
   (the `untagged` control wins; `permsolo` reproduces the interference).
2. a note on `RESULTS-mtp-2026-10-21.md` and `RESULTS-adapter-set-2026-10-21.md`
   that their bodies carry **pre-correction** numbers, pointing at
   `MTP-GATES.md` PART 2 and this file.
3. `LINES.md` Row K' updated with the Â§1.0 reading, and Row J's J'-A ratio
   range corrected to "2.4â3.5".

### Lane C â Rust/CPU, ~2 min once compiled: arm E

**Arm E was closed by concurrent work during this session** (see Â§5): the
production path now goes through `LoraAdapter::load_auto`, which _detects_ the
on-disk format and refuses a file in neither layout, and a new test
`tests/mlx_lm_artifact_merge.rs` exercises the trained artifact on the native
surface.

The **verification** of that closure is what remains. Measured this session:

```
tests/lora_set_swap.rs   8 passed; 0 failed   finished in 0.59s
tests/qwen_mtp_parity.rs 3 passed; 0 failed   finished in 0.37s
```

(Those two I ran directly, because the full `cargo test --release` stops at
the first failing suite â the known-flaky `l0_ops_run_and_are_dispatch_cheap`
perf gate â and the lane's own integration suites therefore never ran inside
it. That is a real gap in the release gate: **the suite that would prove this
lane's work is the suite that a flaky perf gate prevents from running.**)

To run the new arm-E suite alongside the other two, once the build lock is
free:

```
cargo test --release --test mlx_lm_artifact_merge --test lora_set_swap --test qwen_mtp_parity
```

**Not verified by me:** the arm-E suite itself. A concurrent agent was
already running the same crates when I tried, and four concurrent cargo jobs
contending for one build directory under load 312 only add contention â so I
stopped my duplicate. **Its result is the concurrent agent's to report; this
plan does not claim it green.**

The `cargo test --release` compile is the expensive part (~45 min under load);
the _tests_ are sub-second. **This lane is compile-bound, not GPU-bound**, so
it overlaps Lane A freely.

### 6.1 The rule that makes this work

> **Never train to answer a scoring question.** Train once per adapter shape;
> answer every scorer, baseline, threshold and reading question from the
> cached completions in Tier 0 (1 s, parallel). Reserve the ~18-minute GPU
> tier for the questions that genuinely need a new adapter.

The lane has already paid this bill twice: the think-echo defect (C-4's
sibling) and the substring scorer (C-4) were both _scoring_ defects found
_after_ an 18-minute arm had already been run. Both were fixable in a second
against cached completions.

### 6.2 What is deliberately NOT scheduled

| Not scheduled                                | Why                                                                                                                                                           |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| An MTP attention head                        | J'-G4: the cost structure is the killer; attention raises per-head cost without touching it. J'-G0 fired NOT FLAT, so no MTP arm is bought at any acceptance. |
| More MTP acceptance arms on the current head | J'-G2: invalid â in-sample 0.9015 vs held-out 0.1235, and _below_ a trivial bigram baseline.                                                                  |
| A rank / target-module sweep                 | K'-G1..G4 must pass first; a shape sweep on an unmeasured base optimizes an unknown.                                                                          |
| A 4-bit dequantâmergeârequant path           | No product consumer, no FFI surface, and the requantization error is the same order as the adapter delta.                                                     |
| Re-running J'-A for a third confirmation     | It fired, it is reproducible, and it cost 53 s. A confirmation is a Lane-B action, not a new arm.                                                             |

---

## 7. The durable-ledger gap (arm D) â a mechanical fix, still open

`bench/` is gitignored in this package (`.gitignore`: `/bench*/`), so
`git ls-files bench/` returns **0**: every `RESULTS-*.md`, every arm JSON and
every completion file evaporates on clone. `LINES.md` (created 17:00 today)
and `MTP-GATES.md` are both **tracked-able** (verified: `git check-ignore`
does not match them) and are the fix in progress.

Three gaps remain in it:

1. `LINES.md` Row K' points at
   `bench/nursery/experiments/RESULTS-adapter-conditioning-2026-10-21.md`,
   which **does not exist** â the completed run wrote a JSON
   (`adapter-conditioning-2026-10-21.json`) and a replay JSON, and no RESULTS
   markdown has been written for either.
2. `LINES.md` Row J records the J'-A ratio as "2.8â3.5 across runs"; this
   session measured **2.428**. Both are above the 1.50 NOT-FLAT threshold, so
   the verdict is unchanged, but the range should read "2.4â3.5".
3. `LINES.md` Row K' still needs the Â§1.0 reading: the control arms beat the
   tagged arm, so the frozen reading's conclusion ("recoverable _by
   conditioning_") does not match the data.

Also still open: `bench/nursery/experiments/RESULTS-mtp-2026-10-21.md` and
`RESULTS-adapter-set-2026-10-21.md` carry the **pre-correction** numbers
(0.359 acceptance, â0.847 interference, the "flat in k" series). The
corrections live in `MTP-GATES.md` PART 2 and in this file; the RESULTS
documents still assert the old readings. A reader who opens a RESULTS file
first gets the wrong story â and those files are the ones a later agent is
most likely to open.

**The rule that closes it:** a verdict lives in a _tracked_ file; the
artifact it names lives in `bench/` and is referenced by path. A result that
only exists in a gitignored directory is a result that evaporates, and the
next agent re-runs a closed line.

---

## 8. Non-claims

- Every number here is **one machine (M1, 16 GB), one model
  (Qwen3-0.6B-4bit), one corpus, one seed, one held-out split**. No
  confidence interval is claimed for the adapter accuracies.
- The load average was **309** during these measurements; the _ratios_ and
  _accuracies_ are the measurements, the absolute wall clocks are not
  baselines for future runs.
- The `untagged`-beats-`cond` comparison is **one run, one split**. It is
  strong enough to make the pre-registered reading's _conclusion_ suspect
  (the reading says "by conditioning"; the data says "without it"), and it
  is not strong enough to stand alone as a new verdict. The disjoint
  option-list arm is what settles it. The paired McNemar p-values for the
  perm and veto differences (0.185 and 1.000) are **not** evidence of
  equivalence â they are evidence of _no detectable difference_ at n = 150.
- The McNemar intervals on the control comparisons are Wald intervals on the
  paired difference; they are reported alongside the exact binomial p, not
  in place of it.
- The bigram reproduction used a 36/12 split of the 48 greedy prompts; the
  recorded figure's exact pool definition is not recoverable from the tree,
  which is itself part of C-11.
- Nothing here changes a frozen gate, a threshold, or a pre-registered
  reading. Where the record is wrong, this file says so and names the
  evidence.
- Nothing here touches the harness, the world, or the decision lane.

---

# Part B — the acceleration program (2026-10-21 evening)

The experiment line is decided (see the evening STATUS block). What follows is
not another mechanism question; it is the question of how cheaply the settled
answer can be reached, and two controls that can close the LoRA line outright.
The gates are **L-G1..L-G7** in [`MTP-GATES.md`](MTP-GATES.md) Part 4, frozen
before any arm below runs. The ledger row is **Row M — the acceleration
program** in [`LINES.md`](LINES.md). This section records the cost, the arms,
and the order. It changes no gate.

## B.1 The cost ladder

What each kind of arm costs, from the lane's own measurements. Absolute clocks
are a non-claim on this box (the same prebuilt binary took 53 s quiet and
4 m 47 s contended); the **ordering** is the measurement, and it is not close.

| kind                                                                           | cost                    | basis                                                                                                                                                                                           |
| ------------------------------------------------------------------------------ | ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| replay scorer over the 10 cached cells                                         | **0.183 s**             | recorded for `fast_score.py` over the 10 completion cells. A re-run this session printed **0.22 s** (real 0.35 s) for the same 10 cells. Sub-second either way; the third digit is a non-claim. |
| no-training inference arm (few-shot, ranking, a prompt-shape or batched bench) | **≈ 2–5 min** | a cell eval measured ~51 s; an inference arm is a handful of cell evals and no training. An estimate, not a measured arm.                                                                       |
| a training arm                                                                 | **≈ 18 min**       | 995 s (`untagged`), 1084 s (`cond`); the `shared` arm's training alone **1338 s**. Measured.                                                                                                    |
| a third task                                                                   | **≈ 1.5 h**        | corpus plus arm. An estimate — the corpus does not exist yet, so this is reasoning time, not machine time.                                                                                 |

The gap that matters: the replay scorer is ~6000× cheaper than a training arm,
and an inference arm is ~4–9× cheaper. That gap is the whole program.

## B.2 The four inference-only arms

No training. Each reuses the base model or the one adapter already trained.

| arm                    | gate     | what it asks                                                                                                           |
| ---------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------- |
| few-shot               | **L-G1** | does the base, given 8 exemplars, already match `untagged`?                                                            |
| ranking                | **L-G6** | does argmax over the legal labels' log-probabilities, length-normalized, match `untagged` on the same items?           |
| the batched bench      | **L-G4** | aggregate tok/s at concurrency 1/2/4/8/16, forced-eval, interleaved; batch invariance is a precondition, not a detail. |
| the prompt-shape bench | **L-G5** | per-task list vs the shared union: prompt bytes, prefill wall, peak KV, prefix-cache hit rate, at concurrency 1 and 8. |

## B.3 The two training arms

Conditional. Bought only if the inference-only arms do not already close the
line.

| arm                                                                                        | gate     | cost                        |
| ------------------------------------------------------------------------------------------ | -------- | --------------------------- |
| the noise control — same corpus, labels randomized                                    | **L-G2** | ≈ 18 min               |
| the third, dissimilar task — disjoint labels, majority < 0.5, every label represented | **L-G7** | ≈ 1.5 h (corpus + arm) |

## B.4 The single biggest acceleration

**Make the experiments inference-only.** Train ONE adapter, reuse it, and treat
the PROMPT as the cheap variable. Every option-list, exemplar, answer-space and
ranking question then costs 2–5 min instead of 18 min — and the replay scorer
answers any question about a _completed_ run in well under a second. A training
arm is bought only for a question that needs a **new model**: the noise control,
and the third task. Nothing else in this program needs one.

## B.5 The pre-registered order

**Run the cheap arms first, because L-G1 and L-G6 can each close the entire
line on their own.** A closed line needs no third task and no noise adapter, so
the expensive arms are conditional on the cheap ones failing.

1. **L-G1 (few-shot) and L-G6 (ranking), first.** Inference-only, minutes each.
   If EITHER passes, the LoRA line closes and steps 3–4 are not bought. (A PASS
   on either of these closes the line; a FAIL keeps it open. The direction is
   the reverse of every earlier gate in this lane — read it in the gates file,
   not from habit.)
2. **L-G4 (batched bench) and L-G5 (prompt-shape bench), alongside.** Also
   inference-only, and they decide what the acceleration program rests on
   regardless of how the line closes. L-G4's batch-invariance precondition is
   checked before its ratio is quoted.
3. **L-G2 (noise), only if L-G1 and L-G6 both FAIL.** The format question is
   live only if a no-training path did not already match the adapter.
4. **L-G7 (third task), only if the line is still open after step 3.** It is
   the most expensive arm in the program, and it answers a question the cheap
   arms may already have made moot.

**The rule under the order.** An arm that can close the line runs before an arm
that can only refine it. Ordering by "which question is most interesting" would
spend 1.5 h on L-G7 before learning that L-G1 ended the program in five
minutes.
