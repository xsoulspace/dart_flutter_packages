# PYTHON-BOUNDARY.md — which Python may move to Rust, and what may not

**Why this file exists.** The model-experiment lane now has a working
acceleration program, and the obvious next question is "the training and the
generation are Python — should the numerical stack move to Rust so the
experiments run faster?" This file answers that question with the lane's own
measurements, so the next agent does not spend a sprint re-deriving it. It is
a **boundary**, not a campaign: most of the Python here stays in Python, and
the reason is arithmetic, not taste.

**The scope.** This is about the **experiment lane's Python** — the
`tool/nursery/` tools, the driver, the scorer, the dataset generators — and
the Rust crate it drives (`native/mlx_native`). It is NOT about the
inference product's Python (there is none) and NOT about the harness.

**The clock law applies here too.** Under [POWER.md](POWER.md)'s laws the
absolute milliseconds on this box are non-claims when the real charge current
is unknown (the 2026-10-21 arms ran on a 58 mA brick, ≈0.66 W). So the
**order of magnitude and the ratios** are the measurements; the third digit
of a wall-clock number is not.

---

## 1. The measured facts

| fact                                                | number                                                                                                   | where it comes from                                                                            |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| one **training arm**                                | **≈ 18 min** — 995 s (`untagged`), 1084 s (`cond`); the `shared` arm's training alone **1338 s**         | `EXPERIMENT-PLAN.md` B.1; `adapter-conditioning-shared-2026-10-21.json` (`elapsed_s = 1338.5`) |
| the **replay scorer** over the 10 cached cells      | **0.183 s** (a re-measurement printed **0.22 s**, real **0.35 s**)                                       | `EXPERIMENT-PLAN.md` B.1                                                                       |
| the ratio between them                              | the replay scorer is **~6000×** cheaper than a training arm                                              | `EXPERIMENT-PLAN.md` B.1                                                                       |
| a **no-training inference arm**                     | **≈ 2–5 min** (a cell eval measured ~51 s)                                                               | `EXPERIMENT-PLAN.md` B.1                                                                       |
| **evaluating 300 generations** (2 cells × 150 rows) | ≈ **1.7 min** — a _minor_ part of an arm (≈ 8 % of the `shared` arm's 1338 s)                            | derived from the two rows above; the arithmetic is stated, the inputs are cited                |
| plain-greedy **decode**                             | **82.0 – 86.4 tok/s**                                                                                    | `bench/nursery/experiments/RESULTS-mtp-2026-10-21.md` §3                                       |
| the **tied vocabulary projection**                  | **94.5 % of a bf16 body step** (33 % of a 4-bit body step); the embedding table is **311 MB** in bf16    | `RESULTS-mtp-2026-10-21.md` §0.2                                                               |
| the **batched body forward** is **NOT flat**        | `body(8)/body(1) = **2.0–3.5**` (banded; the gate's flat threshold is 1.15, the NOT-FLAT threshold 1.50) | `LINES.md` Row J; `MTP-GATES.md` Part 2 (C-1)                                                  |

**The binding constraint is bytes per token, not compute.** The lane's own
measurements point the same way from three directions: the largest single
cost in a step is a _weight read_ (the tied projection, 94.5 % of a bf16 body
step), the device is memory-bound, and the batched body forward does not
amortize its extra positions (2.0–3.5× at 8 positions — a per-token cost that
grows with the batch, not a fixed cost that gets shared). A driver that
changes _scheduling_ can therefore change throughput; a driver that changes
_arithmetic_ cannot buy FLOPs this device was not already spending.

---

## 2. What is NOT worth porting, and why

This is the important half. Each entry names the specific thing, the specific
number that kills it, and the specific harm a port would do.

### `numpy` / `scipy` / `pandas`

**Measured:** the scoring path **does not import numpy at all** —
`tool/nursery/scoring.py` imports `math`, and `tool/nursery/fast_score.py`
imports only the standard library (`argparse`, `hashlib`, `json`, `math`,
`os`, `sys`, `time`, `concurrent.futures`). **scipy and pandas are not
imported anywhere in the lane's Python.** numpy appears in the lane only in
the _training/weight_ path (`model_def.py`, `safetensors.numpy`), which runs
inside `mlx_lm`'s own trainer.

**Why it does not pay:** the whole scoring path costs **0.183 s**. Porting it
buys roughly **0.02 %** of a 1000 s cycle. That is four orders of magnitude
below the noise floor of a contended box, where the same prebuilt binary took
53 s on a quiet machine and 4 m 47 s on a loaded one.

**Why it actively hurts:** it **adds a second copy of the rules**. The lane's
two worst defects were both _definition_ defects (C-4, a bare-substring
scorer that read `abandoned` as `done`; C-11, a gate that read one arm and
so could not see its own controls). A duplicated definition of a rule is a
correctness hazard, not a speed problem. Porting the numeric stack is the
cheapest way to make that class of defect worse.

### The `mlx` / `mlx-lm` GPU runtime

**Measured:** it is already Metal/C++ with Rust bindings in this repo. The
crate statically links the pinned **MLX 0.32.2 + mlx-c** sources
(`native/mlx_native/Cargo.toml`, `src/mlx.rs`, `src/bindings.rs`).

**Why it does not pay:** a Rust driver cannot make a 4-bit matmul faster. The
kernels are the same kernels, on the same Metal stack, and the arithmetic is
identical. What a driver _can_ change is how work is scheduled — which is
exactly what §3.1 is about, and it does not require re-implementing MLX.

### The dataset generators

**Measured:** CPU work, seconds (`tool/nursery/veto_branch_dataset.py`
regenerates its corpus byte-for-byte from a seed).

**Why it does not pay:** they are not on any hot path, and they are **where
the domain discipline lives** — the frozen-case assertions, the
label-disjointness checks, the non-degeneracy bars (majority class < 0.5,
every label represented) that keep a control arm from being trivial. Porting
them risks the law for no gain.

### The LoRA trainer

**Measured:** same kernels, same corpus, same ~18 min.

**Why it does not pay:** a Rust trainer re-implements the optimizer without
buying FLOPs. It would buy **determinism** and **one-engine reuse** — and
those are a _product_ concern (one engine, one set of invariants), not a
speed one. They do not make the next experiment cheaper than the ~2–5 min an
inference-only arm costs, and the program's own answer (below) is that
inference-only arms should replace training arms wherever they can.

---

## 3. What IS worth porting, and why

Three items, ranked by measured payoff. **Two of the three are not speed
arguments.**

### 3.1 The generation hot loop — the one unmeasured speed lever

**What it is.** The Python driver calls `mlx_lm.generate` **once per prompt**,
single-stream (`tool/nursery/adapter_conditioning.py`: `from mlx_lm import
generate`, called inside the per-item loop). There is no batching, so the
device is used at one sequence's worth of bandwidth.

**Why it might pay.** Decode is **bandwidth-bound on the weights** (the
tied projection alone is 94.5 % of a bf16 body step), so the FLOPs are
unchanged by concurrency but the **scheduling** is not: several sequences can
share one weight read. A batched native path is the one lever in the program
whose payoff has not been measured at all. The plausible band is **3–6×**
aggregate tok/s — that is an **ESTIMATE, not a measurement**; the gate's own
threshold is 1.5× (L-G4), and a miss there closes the batching lane the way
J'-G0's NOT-FLAT closed the MTP lane.

**What it costs to find out.** This is a **gate**, not a project:
[`MTP-GATES.md`](MTP-GATES.md) **Part 4, L-G4** — aggregate tok/s at
concurrency 1/2/4/8/16, forced-eval, interleaved, with **batch invariance as
a PRECONDITION** (if a sequence's output depends on its position in the
batch, every number measured through that path is a function of a choice, and
a function of a choice is not a measurement). The measurement is a native
bench (`qwen_batch_bench.rs`) over a batched native path (`qwen_batch.rs`);
**neither file is in the tree yet**, so building them IS the port.

**What it does NOT buy.** It does not make the body forward flat — it is
measured **not** flat (2.0–3.5× at 8 positions). It buys scheduling, not
arithmetic.

**Porting the driver is what makes batching possible.** The gate itself
(`qwen_batch_bench.rs` / `qwen_batch_bench`) is a native measurement; a
Python driver cannot express a batched decode with a per-sequence KV, so the
measurement and the port are the same piece of work.

### 3.2 The scorer — for ONE owner, not for speed

**Measured:** 0.183 s over 10 cached cells. Porting it for speed would buy
nothing at all.

**Why it is still worth doing.** The gate rules currently exist **twice** in
Python: `fast_score.py` and `adapter_conditioning.py`, and the lane's two
worst defects were both definition defects. `tool/nursery/scoring.py` is now
the **canonical single-definition module** — the strict extractor, the legacy
extractor, the matched trivial baseline, coverage, and the exact McNemar test
live there once, and `adapter_conditioning.py` imports it, and `fast_score.py`
imports it through that.

**The residual is the honest part:** `fast_score.py` still carries its own
copies of the trivial-baseline helpers (`trivial_from_items`,
`trivial_on_scored_rows`), and the lane's tools are Python while the product's
language is Rust. **One owner, in the product's language, is the fix** — not
"a faster scorer", which was never the problem.

### 3.3 Nothing else, yet

**And the rule that says so:**

> **A Python library earns a Rust port only if it (a) sits on a measured hot path, (b) has a second copy of a rule that can drift, or (c) is a correctness hazard. Everything else stays in Python.**

Test it against the list in §2 and it holds: numpy fails all three,
`scipy`/`pandas` are absent, the `mlx` runtime fails (a), the generators fail
(a) and are a correctness asset, the trainer fails (a) for speed but is a
legitimate (b)/(c) candidate for a _product_ reason — which is a different
decision, taken by a different owner, at a different time.

---

## 4. The real acceleration is structural, not a port

The port makes the **measurements** cheaper. The structure makes the
**experiments** cheaper. Both are needed; neither substitutes for the other.

| lever                                                | what it turns an experiment into                                                                                                                   |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| **train ONE adapter and reuse it**                   | every prompt-shape, option-list, exemplar and ranking question costs **≈ 2–5 min** instead of **≈ 18 min** — the prompt becomes the cheap variable |
| **cache the observation, replay the interpretation** | already done: a training arm's worth of questions answers in **0.183 s**                                                                           |
| **coverage-complete scoring**                        | L-G3: a number with coverage < 1.0 is `partial` and is not a gate input — cheap _and_ honest                                                       |
| **the two no-training arms that can close the line** | L-G1 (few-shot) and L-G6 (ranking) are inference-only, minutes each, and **either passing ends the LoRA line**                                     |

**The port makes the MEASUREMENTS cheaper; the STRUCTURE makes the EXPERIMENTS
cheaper.** A faster trainer would make a training arm 18 → 12 min. The
structure removes the training arm entirely from most of the program, and
removes the expensive arms conditionally (L-G2 and L-G7 are bought only if
the cheap ones fail). The order and the cost are frozen in
[`EXPERIMENT-PLAN.md`](EXPERIMENT-PLAN.md) Part B; the gates are in
[`MTP-GATES.md`](MTP-GATES.md) Part 4; the ledger row is **Row M — the
acceleration program** in [`LINES.md`](LINES.md).

---

## 5. A "we tried to port X and it bought nothing" note

**The non-example: `numpy`.** The scoring path is 0.183 s and does not import
numpy; scipy and pandas are not imported anywhere in the lane. A port buys
~0.02 % of a 1000 s cycle **and** adds a second copy of the rules — the exact
defect class (C-4, C-11) that cost the lane two defects already. **Do not
re-open this.** The same argument disposes of `scipy` and `pandas` without a
measurement, because they are not in the tree at all.

**The second non-example: the `mlx` GPU runtime.** It is already Metal/C++
with Rust bindings in this repo; a Rust driver cannot make a 4-bit matmul
faster. The only thing a driver can change here is **scheduling**, which is
the L-G4 batched-decode lever and is worth measuring once.

**Non-claims.** Nothing here claims that Python is fast, that Rust is fast,
or that a port would be neutral: a port of the _scorer_ would remove a real
second copy of a rule, and that is a correctness argument, not a speed one.
The numbers above are one machine, one model, one corpus, one seed.

## Cross-references

- [`MTP-GATES.md`](MTP-GATES.md) **Part 4** — **L-G4** is the batched-decode
  gate (with batch invariance as a precondition); **L-G1** and **L-G6** are
  the no-training arms that can close the line.
- [`LINES.md`](LINES.md) **Row M** — the acceleration program's ledger row.
- [`EXPERIMENT-PLAN.md`](EXPERIMENT-PLAN.md) **Part B** — the cost ladder, the
  arms, and the pre-registered order.
- [`POWER.md`](POWER.md) — the clock law: absolute milliseconds on this box
  are non-claims; ratios are the measurement.
