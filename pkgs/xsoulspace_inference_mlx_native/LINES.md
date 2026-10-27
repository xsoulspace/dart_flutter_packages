# LINES.md — the model-experiment lane's durable ledger (tracked)

**Why this file exists.** `bench/` is gitignored in this package
(`.gitignore`: `/bench*/`), so the lane's spine — `LINES_PLAN.md`, `HISTORY.md`,
and every `RESULTS-*.md` — was **untracked**: a clone saw the frozen gates
(`MTP-GATES.md`, tracked) and **no results**. A negative result that only
exists in a gitignored directory is a negative result that evaporates, and the
next agent re-runs a closed line.

This file is the tracked summary: **rows, verdicts, where the evidence lives,
and what is NOT claimed.** The full artifacts stay under `bench/` (working
material, gitignored by design); this file is what binds them.

**How to use it.** Read this file, then `MTP-GATES.md` (the frozen gates and
the pre-registered readings), then the `RESULTS-*` file named in the row for
the full numbers. If a row's verdict and its evidence disagree, the evidence
wins and this file is wrong — fix it here.

**Classification and history.** [`VERDICTS.md`](VERDICTS.md) is the one-screen
classification layer over these rows — what **failed at all** (F), what was
**measured wrong** and is void (V-s superseded / V-r remeasure owed), what is
closed only on this device/config with a **named reopen condition** (C), and
what is **open** (O) — plus the current path forward.
[`RESULTS-HISTORY.md`](RESULTS-HISTORY.md) tabulates every recorded
measurement with its date, value, gate and class. Read VERDICTS first when the
question is "where do we stand and what is next"; read this file for the
row-level detail.

**The discipline that produced it** (see `bench/nursery/META-LESSONS.md`): a
threshold is written BEFORE the run; a failure gets a pre-registered reading;
a number without its trivial baseline is not a number; a result that lives
only in an untracked file is not a result.

---

## Row J — MTP (multi-token prediction) as a SPEED technique

**Verdict: CLOSED on this device, for a measured reason.**

|                     |                                                                                  |
| ------------------- | -------------------------------------------------------------------------------- |
| Gates               | `MTP-GATES.md` J-G1..J-G5 (frozen 2026-10-21 before the run)                     |
| Evidence            | `bench/nursery/experiments/RESULTS-mtp-2026-10-21.md`                            |
| Native port         | `native/mlx_native/src/qwen_mtp.rs` (token-exact vs plain greedy: 0 divergences) |
| Native bench        | `native/mlx_native/src/bin/qwen_mtp_bench.rs`                                    |
| Marginal-cost bench | `native/mlx_native/src/bin/qwen_marginal_cost.rs` (J'-A, below)                  |
| Corrected record    | `MTP-GATES.md` Part 2, corrections C-1..C-10                                     |

**What was measured.** Acceptance (P(draft == trunk's next argmax), decode-
consistent, on the trunk's own greedy path) reached **0.124** against a 0.60
gate. The native port ran at **0.42×** plain greedy. The count line closed at
count 1 (depth-2 acceptance 0.015).

**WHY it is closed (the corrected reason, C-1/C-5).** Two things, both
measured:

1. **The batched forward is NOT flat in position count.** J'-A measured the
   trunk body at 1/2/4/8 positions, forced-eval, with the tied projection
   timed separately: `body(8)/body(1) = **2.0–3.5**` across runs (the gate's
   flat threshold is 1.15; the NOT-FLAT threshold is 1.50). The marginal cost
   of one extra verified position is **~2–4 ms** against a **~30 ms** AR token.
   The 2026-10-21 record's "nearly flat in k" series (0.688/0.682/… ms) has
   **no producing artifact in the tree** and is contradicted by the same
   document's own forced-execution table by ~39×.
   **The band, not the point.** Three runs on this machine measured 2.8–3.5
   (recorded), 2.428 (2026-10-21) and **2.034** (2026-10-21, 18:0x, on a
   saturated box). The VERDICT is robust — every measurement is far above the
   1.50 NOT-FLAT threshold, with a 1.36x margin even at the low end — but the
   ratio itself moves ~1.75x across runs, so it is quoted as a band. The
   absolute milliseconds are **not** a baseline: the same prebuilt binary took
   **53 s on a quiet box and 4 m 47 s on a loaded one** (19.5 s of CPU in
   287 s of wall — 93 % of the wait was GPU/IO behind other work), and the
   marginal cost measured 11.9 ms/position on the loaded box against the
   ~2–4 ms quoted above. Only the ratio is the measurement.
2. **The port's token accounting cannot win by construction (C-5).** It
   commits `max(accepted_prefix, 1)` tokens per round, and at K=1 a
   depth-0 draft competes with the token the trunk ALREADY holds — so a
   round never commits more than one token, while paying the verify, the
   draft head, and (on a rejected round) a resync forward. The gate's own
   formula assumed `1 + accepted_prefix`. **The recorded "0.91× at p=1.0" is
   the port's accounting, not the gate's.**

**J'-A, the gate that decides whether Line J' exists (MTP-GATES.md J'-G0).**
VERDICT: **NOT FLAT** ⇒ MTP-as-speed is closed on physics for ANY acceptance
⇒ **no MTP arm is bought**. K=2 is unreachable at any acceptance. The
measurement is a new binary (`qwen_marginal_cost`) that: forces the ACTUAL
output of every timer (MLX is lazy — a dummy eval measures graph
construction, a measured 28.7× error), reserves the KV cache OUTSIDE every
timer, **interleaves** the position counts so thermal drift cancels instead
of biasing the ratio, and reports the AR reference BEFORE and AFTER the
sweep so the ordering bias is measured rather than assumed.

**What this does NOT say.** Not that MTP is a bad technique in general; not
that an attention-equipped head could not accept better (that arm was never
started and has a weak prior — J'-G4 does not buy it); not that a device with
a cheaper vocabulary projection or more bandwidth could not pay. It is a
verdict about **this** trunk on **this** device, and the acceptance number
stays useful for such a device.

**The one measurement that would change this verdict:** a body forward that is
genuinely flat in position count (`body(8)/body(1) <= 1.15`) on this
hardware. J'-A measured 2.8–3.5, so that is a hardware fact, not a
re-run.

---

## Row K — the swappable LoRA adapter set

**Verdict: the MECHANICAL surface is proven; the CAPABILITY is real and
larger than the 2026-10-21 record claimed; the SET of swappable specialists is
NOT justified — and the 2026-10-21 capability number did not survive
re-measurement (C-4/C-10).**

|                 |                                                                                                         |
| --------------- | ------------------------------------------------------------------------------------------------------- |
| Gates           | `MTP-GATES.md` K-G1..K-G4 (2026-10-21), K'-G1..K'-G6 (2026-10-21)                                       |
| Evidence        | `bench/nursery/experiments/RESULTS-adapter-set-2026-10-21.md`                                           |
| Rust surface    | `native/mlx_native/src/lora_set.rs` (swap, cache key, quantized refusal)                                |
| Format bridge   | `native/mlx_native/src/lora.rs` — `LoraAdapter::load_mlx_lm` (loader only; **no call site yet**)        |
| K' evidence     | `bench/nursery/experiments/RESULTS-adapter-conditioning-2026-10-21.md` (the K' re-ask)                  |
| Re-measurement  | `tool/nursery/adapter_conditioning.py` (NEW), `tool/nursery/veto_branch_dataset.py` (NEW)               |
| Fast replay     | `tool/nursery/fast_score.py` (NEW) — every gate question from the cached completions, no GPU            |
| Cached evidence | `bench/nursery/experiments/adapter-conditioning-2026-10-21/` (completions + adapters + sha256 manifest) |

**What the mechanical surface proves** (unaffected by every correction):
the swap is **byte-for-byte reversible** (adapter off ⇒ base, f32 bit
patterns, no compounding); the cache key carries the adapter digest and the
epoch increments on every swap including back to base; a **quantized base is
refused at bind**, not approximated.

**What the 2026-10-21 arm got wrong (C-4).** The measured collapse
(−0.847 on the cross-task cell) was scored with a **bare substring search**,
so `abandoned` matched `done`, `transaction` matched `action`, `satisfaction`
matched `fact` **and** `action`, and `reopened` matched `open`. The
artifact's own `outside_label_set = 0` on that cell **contradicts** the prose
that said the adapter "stopped answering in the clause label set at all". The
DIRECTION (an adapter that does not transfer) was real; the SIZE was a
scoring artifact of the same class as the think-echo defect this lane had
already paid for once.

**What the 2026-10-21 arm also could not claim (C-10).** It ran the **python
mlx-lm runtime-adapter path**, and the Rust surface **could not load that
artifact at all** — `mlx_lm` writes `lora_a`/`lora_b`, the Rust loader
accepted only PEFT `lora_A.weight`/`lora_B.weight`. So the +0.153 was never a
native-surface number.

**C-10 is CLOSED (2026-10-21, Arm E's three items).** The bridge now has a
call site, the format is DETECTED rather than assumed, and the gate that
proves it runs in the default suite:

1. **A call site.** `LoraAdapter::load_auto` picks the loader by DETECTING
   the on-disk layout from the tensor names (mlx-lm `*.lora_a`/`*.lora_b` vs
   PEFT `*.lora_A.weight`/`*.lora_B.weight`) and **REFUSES** a file in
   neither layout — or in both — instead of guessing.
   `NurseryModel::load_with_adapter` calls it, so the FFI
   `mlx_native_nursery_model_load_with_adapter` inherits it.
2. **The parity tests run.** `mlx_lm_and_peft_formats_merge_identically` and
   `zero_adapter_is_identity` are no longer `#[ignore]`d, and
   `the_format_is_detected_not_assumed` covers the refusal path. **27 lib
   tests pass, 0 fail** (`cargo test --release --lib`).
3. **The trained artifact loads and merges** — the new gate
   `tests/mlx_lm_artifact_merge.rs` loads the artifact this lane actually
   trained (`adapter_cond/adapters.safetensors`), checks every pair's shape,
   verifies the merge delta is exactly `scale * (B @ A)` on the smallest
   pairs (a transposed orientation would show up here), applies every pair
   into a synthetic base, and asserts a missing target is a hard error.
   **1 passed, 0 failed** — and it _skips loudly_ (not silently) when the
   artifact is absent, because `bench/` is gitignored.

**The defect the ignore was hiding.** The two tests were not slow, they were
UN-RUNNABLE: the lib test binary created a Metal stream before any kernel
library was pinned, and MLX aborted inside `default_stream`
(`stream.cpp:176`, "vector at ..."). The fix is the crate's own
`pin_metallib_colocated()`, now called from `mlx::gpu()` — so the pin
happens before the FIRST stream no matter which test gets there first, and
the candidate list now prefers the build root the crate linked its mlx-c
against (the metallib that MATCHES that build). The `#[ignore]` was hiding a
defect, not the cost.

**Line K' — the re-ask (MTP-GATES.md K'-G1..K'-G6).** Strict scoring (a
completion must EQUAL a label), per-item outcomes persisted, the adapter
artifacts kept, a **non-degenerate** second task (VETO-BRANCH-4: labels
disjoint from perm's, majority 0.25, every label represented), and
**conditioning** (an explicit `Task:` tag at train and test time, with
`mask_prompt=True` so the loss lands on the answer tokens only). Result:
`bench/nursery/experiments/RESULTS-adapter-conditioning-2026-10-21.md`.

**K' VERDICT: the capability is real and LARGER than the 2026-10-21 record
claimed; the selectivity is NOT attributable to the conditioning tag.**

One base (Qwen3-0.6B-4bit), two disjoint-label tasks, 150 held-out rows per
cell, strict scoring, baselines matched to the scored rows:

| arm      | trained on | tagged  | option list shown      | perm       | veto       | Δ vs trivial (perm / veto)                                        |
| -------- | ---------- | ------- | ---------------------- | ---------- | ---------- | ----------------------------------------------------------------- |
| base     | —          | no      | —                      | 0.4533     | 0.2400     | −0.0933 / −0.0333 (at the trivial baseline: it does neither task) |
| cond     | both       | **yes** | the task's own labels  | 0.8200     | 0.7733     | **+0.2733 / +0.5000**                                             |
| untagged | both       | **no**  | the task's own labels  | **0.8733** | **0.7800** | **+0.3267 / +0.5067**                                             |
| permsolo | perm only  | no      | the task's own labels  | 0.9600     | 0.1733     | +0.4133 / **−0.1000** (damages the unseen task below trivial)     |
| shared   | both       | no      | **the union of all 6** | 0.7867     | 0.7133     | +0.2400 / +0.4400 (still transfers with NO task signal)           |

**The control arms decide the attribution.** `untagged` — the same two-task
training with no tag — is at least as good as the tagged arm on both tasks.
Paired (same items, exact McNemar): perm 28 discordant, Δ −0.0533, 95 % CI
[−0.1219, +0.0153], p=0.185; veto 17 discordant, Δ −0.0067, CI
[−0.0605, +0.0472], p=1.000. Neither is significant and both point negative:
**the `Task:` tag is not load-bearing.** The prompt already carries the
conditioning signal — the legal label set — so the tag is redundant.

`permsolo` (one task instead of two) names what **is** load-bearing: the
multi-task data. Against `cond` it is −0.1400 on perm (CI [−0.2014, −0.0786])
and +0.6000 on veto (CI [+0.5095, +0.6905]), both p<0.001 — it wins on the
task it trained on and **damages the task it never saw** (0.1733, below the
0.2733 trivial baseline). The transfer is bought by the second task's data, at
a measured cost on the first (0.9600 → 0.8733 → 0.8200).

**The gate defect this exposed (C-11, `MTP-GATES.md` Part 3).** Parts 1-2 of
the gates mention `untagged`/`permsolo`/`control` **zero** times, and
`evaluate_gates` reads `arms["cond"]` only, so reading 1 was **unfalsifiable
as encoded** — it would have fired even if conditioning had contributed
nothing. K''-G1 (Part 3) adds the control contrast, with the measured result
and with reading 1's _causal_ half withdrawn while its _product-shape_ half
stands.

**The `shared` arm closes the mechanism question** (the pre-registered
arm from `EXPERIMENT-PLAN.md` §4): one option list for BOTH tasks, so the
prompt names no task at all — and it **still transfers** (+0.240 perm, +0.440
veto, both over the matched trivial baseline, no unconditional prior). Paired
vs `untagged`: perm Δ +0.0867, 95 % CI [+0.0177, +0.1557], p=0.024; veto
Δ +0.0667, CI [−0.0153, +0.1486], p=0.154. The nine out-of-set answers in
shared/veto are **all `abstain`** (a perm-family label) on items whose gold is
`no_grant` — the same decision in the wrong family's vocabulary, which is
only possible if the task came from the **input text**. So the option list is
a _refinement_ (worth ~7–9 points, mostly vocabulary), not the mechanism.

**The complete attribution:** the **multi-task training data** is
load-bearing (`permsolo` collapses on the task it never saw); the **`Task:`
tag** is not (p=0.185 / 1.000); the **option list naming the task** is not
the mechanism (`shared` still transfers) — it is a _refinement_ worth ~7–9
points, and the part of it that matters is **vocabulary**, not task identity.

**The reconciled answer-space rule (identical in both result files):**

> **Per-task answer spaces by default.** A shared answer space is defensible
> only across a _semantically dissimilar_ group of tasks — a case this lane has
> NOT yet established, because its two tasks (perm, veto) are BOTH permission
> requests. On the pair measured here, the shared list cost ~7–9 points AND
> leaked 6 % of one task's answers into the other's vocabulary, so the leak is
> an UPPER BOUND for dissimilar pairs and the per-task default is confirmed.

The leak is a _class_ of error a product would hit, and a per-task option
list prevents it entirely; "a cost of 7–9 points" understates it, because
those items are already scored as misses and the failure is a **vocabulary**
failure, not a score. The upper bound is the reason the rule is conditional:
`perm` and `veto` are both permission requests, so `no_grant ⇒ abstain` is a
_true_ mapping between them. **L-G7 (a third, dissimilar task) is the gate
that moves this rule from conditional to settled.**

**The product shape that survives the evidence:** **one adapter trained on
all tasks, untagged, prompted with an answer space** — not a set of
swappable specialists, not a tagged one, and the answer space does not have
to name the task. The `lora_set.rs` surface stays over-built and is retained
only as a cheap-to-re-derive negative result.

---

## Row L — the native engine's weight identity (the prefix-cache law)

**Verdict: the cache is now INVALIDATED, not merely keyable.**

|      |                                                                         |
| ---- | ----------------------------------------------------------------------- |
| Code | `native/mlx_native/src/qwen_prefix.rs`, `native/mlx_native/src/qwen.rs` |
| Test | `qwen_prefix::tests::a_weight_change_drops_every_entry`                 |

The 2026-10-21 record named the gap: the live prefix pool produced a
**keyable** cache but did not **invalidate** it. The fix is structural rather
than conventional: the **engine owns its weight identity** (`Qwen3::
weight_identity()`, the checkpoint digest) and the pool **drops every entry**
whose identity differs. A prefix computed under other weights is not a stale
hit — it is a **wrong answer** — so the pool cannot be handed one, and no
caller can forget to invalidate. `lora_set::CacheKey::epoch_token` still
fills the `epoch` slot; this identity is the belt to that braces.

**Non-claim.** Nothing about the harness changed, and the harness's own
prefix-cache behaviour is unchanged (the identity is constant per load). No
claim that the harness will ever use an adapter: the harness's permission
gate is discharged by **Laya** (ADR 0084), not by Qwen3+LoRA.

---

## Row M — the acceleration program (and the two gates that can close the line)

**Verdict: OPEN. The EXPERIMENT line is decided; what remains is the
acceleration program — how this lane gets faster without buying a GPU.** The
program has two halves, and **neither substitutes for the other**: the
STRUCTURE makes the _experiments_ cheaper, the PORT makes the _measurements_
cheaper.

|                 |                                                                                       |
| --------------- | ------------------------------------------------------------------------------------- |
| Gates           | `MTP-GATES.md` Part 4, L-G1..L-G7 (frozen 2026-10-21, before any run)                 |
| Boundary        | [`PYTHON-BOUNDARY.md`](PYTHON-BOUNDARY.md) — the durable port/no-port law             |
| Plan & cost     | [`EXPERIMENT-PLAN.md`](EXPERIMENT-PLAN.md) Part B                                     |
| Rust surfaces   | `qwen_batch.rs` (+ `qwen_batch_bench.rs`), `qwen_rank.rs` (+ `qwen_rank_bench.rs`)    |
| Python surfaces | `tool/nursery/scoring.py` (one definition), `rank_labels.py`, `third_task_dataset.py` |
| Lessons         | `bench/nursery/META-LESSONS.md` 17–20                                                 |

### The measured facts the program rests on

| thing                                  | cost                                                                | note                                                         |
| -------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------ |
| one training arm                       | **≈ 18 min** (995–1084 s; the `shared` arm's training alone 1338 s) | GPU-bound in the same Metal kernels a Rust driver would call |
| one no-training inference arm          | **≈ 2–5 min**                                                       | 300 generations, single-stream                               |
| the replay scorer over 10 cached cells | **0.183 s**                                                         | the observation is cached; the interpretation is free        |
| a third task (corpus + arm)            | **≈ 1.5 h**                                                         | the corpus does not exist yet                                |

**The binding constraint is bytes per token, not compute.** Decode runs
82–86 tok/s single-stream at ~12 ms per AR token, and the tied vocabulary
projection is **94.5 %** of a bf16 body step (a 311 MB table). The batched
body forward is **not flat**: `body(8)/body(1)` = 2.0–3.5 across runs, which
is what closed Line J. So the levers are **bandwidth** (batch the
independent work), **amortisation** (stop re-deriving what was already
measured), and **structure** (do not train when a prompt will do) — not
FLOPs, and not the language a driver is written in.

### L-G4, measured: the lever is real, and the bar is now the DECISION, not the bits

The batch bench (`qwen_batch_bench`, native Rust) ran on 2026-10-21 and
produced the number the acceleration program stands on.

- **The lockstep control is flat to within 0.4 %** across a 16× change in
  concurrency (aggregate tok/s 80.89 → 81.04, ratio 0.996–1.002). Running N
  independent decodes concurrently buys **nothing** on this box, because each
  sequence still does its own weight read. This is not the gate's number; it
  is the baseline a fused batch has to beat, and it is flat because the
  measurement is stable enough to see a real effect.
- **The amortization probe says the lever is worth buying**: the projected
  whole-step ratio is **1.91× at batch 2, 3.66× at 4, 5.39× at 8, 9.95× at
  16** (gate: 1.5 at concurrency 8). The body-layer GEMM is nearly flat
  (1.92 → 2.67 ms from 1 to 8) while the 77.8 MB tied projection grows 3.6×.
- **The bit-level precondition is not met — and bit-identity was the WRONG
  bar.** A batched matmul on the real quantized weights is **not**
  bit-identical to the same row alone (max abs diff 0.0625 body, 0.0239
  projection), and the **same-shape-class control diverges too** — so the
  `gemv`→`skinny_gemm` kernel switch is **not** the explanation; the batch
  dimension is. But **the product's own engine already carries the same
  contract** (`test/laya_native_batch_isolation_test.dart`) and compares the
  **DECISION exactly** with a 1e-3 distribution tolerance — sized to admit the
  measured float16 re-rounding floor (a pure batch-size change moved a
  probability by at most **3.6e-4**) while rejecting a measured
  heterogeneous-batch **short-row defect** (a probability moved by up to
  **0.86**) by three orders of magnitude. That test's own comment: _1e-6/1e-5
  are NOT defensible: they assume the native logits are bit-identical across
  batch shapes, which a float16 trunk cannot deliver._

**So: the lever is real and large, and it is NOT bought yet — but the bar is
now SPECIFIED rather than wished for.** A fused batch must show
**decision-level invariance** (the label does not move with the batch size)
**and no short-row defect on the left-padded path** — the path it must take
for unequal prompt lengths, and a _measured_ hazard on this stack. What is
bought now is the knowledge that the four-part `qwen.rs` change (batch dim
from `tokens.dim(0)`, cache allocated with it, per-sequence offset or
pad+mask, expose the tied embedding) is worth making, the measured bit-level
floor that must be reported beside every fused number, and a precedent and a
tolerance-sizing method already in the tree. Full numbers and non-claims:
`bench/nursery/experiments/RESULTS-acceleration-2026-10-21.md` §1.

### The closing gates, measured: BOTH FAIL, so the line is CONFIRMED

Every arm was re-scored over **every row of the scored split** (293 perm /
227 veto — coverage 1.0000, the only coverage that can be a gate input). Before
this run every L-gate was **refused as partial** (150/293, 150/227) — the gate
working, not failing.

| arm                               | perm       | Δ trivial   | veto       | Δ trivial   | leak (perm/veto) |
| --------------------------------- | ---------- | ----------- | ---------- | ----------- | ---------------- |
| base                              | 0.4403     | −0.1195     | 0.2511     | −0.0308     | 0 / 0            |
| cond (tagged)                     | 0.8328     | +0.2730     | 0.7577     | +0.4758     | 0 / 0            |
| **untagged** (reference)          | **0.8737** | **+0.3140** | **0.7533** | **+0.4714** | 0 / 0            |
| permsolo                          | 0.9761     | +0.4164     | 0.1806     | −0.1013     | 0 / 0            |
| shared (union list)               | 0.8430     | +0.2833     | 0.7004     | +0.4185     | 0 / **14**       |
| fewshot (8 exemplars, no adapter) | 0.5870     | +0.0273     | 0.3348     | +0.0529     | 0 / 0            |
| ranked (no generation)            | 0.4403     | −0.1195     | 0.2291     | −0.0529     | 0 / 0            |

- **L-G1 (few-shot): FAIL** on both tasks (0.5870 vs a 0.8237 threshold;
  0.3348 vs 0.7033). Eight exemplars buy **+0.03 / +0.05** over trivial;
  the adapter buys **+0.31 / +0.47**. The exemplars are not inert — the base
  model's top-label concentration is 1.000 and the few-shot arm's is
  0.809/0.696, so they DO teach it to vary its answer — they just do not
  teach it the **decision**.
- **L-G6 (ranking): FAIL** on both tasks, in **two independent engines**
  (Python/mlx-lm 0.4403/0.2291; native Rust 0.4403/0.2819).
- **L-G2 (noise adapter): RUN 2026-10-26 — MISS on both tasks** (0.5392 vs a
  0.7737 threshold; 0.2511 vs 0.6533; coverage 1.0 both). On veto the noise
  adapter collapses to ONE label (`secret_path`, 227/227) and scores base's
  accuracy to four decimals; on perm it lands BELOW trivial. The format
  explanation of the adapter's gain is measured out, not argued away. Full
  numbers: `bench/nursery/experiments/RESULTS-noise-2026-10-26.md`.
- **L-G7 (third task): RUN 2026-10-26 — PASS, both conditions hold.** On the
  dissimilar pair (perm + instrument-taxonomy; 900-row generated corpus,
  disjoint labels and vocabulary, majority 0.25): shared 1.0000 vs untagged
  1.0000 on the third cell (bar was 0.95), leak **0**, and the two arms'
  completions are **204/204 character-identical** — the union option list
  costs nothing where the tasks share nothing. The pre-registered first case
  fires: *per-task by default; shared is defensible across a semantically
  dissimilar group* (the shared list still cost −0.089 on the perm cell of
  the same run, leak-free). Full numbers:
  `bench/nursery/experiments/RESULTS-third-2026-10-26.md`. **Every Part-4
  gate has now run.**

**So the LoRA line is CONFIRMED as load-bearing**, against the two cheapest
zero-training alternatives (prompting, constrained ranking), both of which
fall far short. That _strengthens_ the adapter line rather than closing it.

**And the base model's failure is a DECISION failure, not a formatting
failure.** `ranked(base)` equals `base`-by-generation on perm (0.4403 vs
0.4403) and within 0.03 on veto: the base model already _ranks_ labels, it
just ranks them the wrong way. **The adapter changes the ranking, not the
output format** — which predicted that L-G2's noise adapter would MISS (the
format prior it would learn is already present in the base). **That
prediction was made from L-G1 and L-G6 before the arm ran, and the arm
CONFIRMED it on 2026-10-26** (MISS on both tasks; the veto collapse to a
single majority label is the format capability in its pure form, worth
+0.000 over the majority baseline).

**Ranking is currently MORE expensive than generation, not less** (native
ratio 0.93 perm / 1.22 veto): the native path does one forward per label
while generation does one forward for the whole answer, because **the fused
batch does not exist**. Ranking's cost advantage is entirely a function of
batching the labels — **the alien idea and the batching lever are the same
lever.**

**A determinism fact fell out of the re-score:** `untagged`'s first 150 rows
re-scored at 293 rows give **131/150 — exactly the recorded number**, and
`cond` reproduces to 0.8328 vs 0.8200. **Greedy generation through `mlx_lm`
is reproducible across runs and model loads** on this box.

### The port law (the answer to "which Python moves to Rust")

**A Python library earns a Rust port only if it (a) sits on a measured hot
path, (b) has a second copy of a rule that can drift, or (c) is a correctness
hazard. Everything else stays in Python.** Applied here:

- **NOT ported: `numpy`/`scipy`/`pandas`.** The scoring path imports **no
  numpy at all** and finishes in 0.183 s — 0.02 % of a 1000 s cycle. Porting
  it would add a second copy of the rules, which is the C-4/C-11 defect
  class.
- **NOT ported: the `mlx`/`mlx-lm` GPU runtime, the dataset generators, the
  LoRA trainer.** The runtime is already Metal/C++ with Rust bindings here; a
  Rust driver cannot make a 4-bit matmul faster. The generators are CPU,
  seconds, and they are where the domain discipline lives (frozen-case
  asserts, label-disjointness checks). A Rust trainer re-implements the
  optimizer without buying FLOPs.
- **PORTED: the generation hot loop** — not for FLOPs, but because a
  _batched_ native path is the one unmeasured lever with a plausible 3–6×
  payoff, and the Python driver calls `mlx_lm.generate` once per prompt.
  **PORTED: the scorer** — not for speed, but to delete a **duplicate
  definition**: the gate rules lived twice in Python, and the lane's two
  worst defects were both definition defects. `tool/nursery/scoring.py` is
  now the single owner.

### What the lane CRITICALLY lacks (the honest gap list)

1. **A coverage-complete score of every arm — DONE (2026-10-21).** All 14
   cells are now at coverage 1.0000 (293 perm / 227 veto), and the L-gates
   are evaluable instead of refused. The `fewshot` and `ranked` arms are
   measured; L-G7 is not — and L-G2 joined the measured set on 2026-10-26
   (MISS), L-G7 on 2026-10-26 (PASS, perm+third, 6 more cells at coverage
   1.0).
2. **The L-G2 noise-adapter control — RUN (2026-10-26), MISS on both
   tasks.** The prediction is now a measurement: the format-only adapter
   scores at base level (veto: one label, 227/227, accuracy identical to
   base to 4 dp). What the real adapter adds is not format.
3. **The L-G7 third task — RUN (2026-10-26), PASS.** Shared answer space is
   legal across the dissimilar group (identical completions, zero leak);
   per-task stays the default on cost. The shared-list cost reappears on the
   policy task of the same run (−0.089, leak-free) — the rule the gate
   wrote, measured on both ends.
3. **The fused batched decode — BUILT (2026-10-26), the lever is bought.**
   The four-part qwen.rs change landed (`qwen_fused.rs` + the batch-generic
   qwen.rs), the reformulated gate is GREEN (classification labels exact
   across solo/B8/B16/positions; co-batching invariance EXACT at 0.0; the
   solo-join floor measured at 0.071 with the positive control at 0.60),
   and the measurement replaces the projection: **1.93× aggregate at B=8,
   3.19× at B=16, AC-baseline** — the ≥1.5 gate clears, the 5.39×
   projection retires against fixed per-step costs. Ranking economics
   flipped conditionally: fused rank 0.80× of sequential at K=4 (the
   prefix-once + cache fan-out design), break-even at K=2. Full numbers:
   `bench/nursery/experiments/RESULTS-fused-tier-a-2026-10-26.md`. The
   fused path is engine-level only — the product surface (QwenEngine /
   serve_text) does not batch yet.
4. **The prompt-shape cost (L-G5) — RUN (2026-10-26), FAIL at the frozen
   terms, conditional recovery measured.** Shared adds +22 tokens/request
   and +55 % cold prefill wall (c=1 AND c=8) — the ≤10 % AND 0-bytes
   clauses fail; at a product-shaped window (2048+ shared tokens) a warm
   prefix pool recovers ALL of it (100 % hit rate, 32–43 ms vs ~1880 ms =
   57× reduction), while per-task lists hit 0 % on every task switch.
   Per-task stays the default; shared is a long-shared-prefix product
   only.
5. **A third, dissimilar task arm** (L-G7) — RUN 2026-10-26, PASS (above).
6. **A native-surface capability number — DONE (2026-10-27).** The
   no-confound option was built: `Qwen3::attach_lora` (runtime LoRA on the
   4-bit base, the mirror of the python path) with its gate
   (`tests/qwen_runtime_lora.rs`). Frozen reading N-G1: **PASS perm (0.8976,
   above python's 0.8737) / FAIL veto (0.6828, −0.02 beyond the margin)**,
   coverage 1.0, leak 0, +0.3379/+0.4009 over matched trivial. Tier B-5 ran
   the same day: **ranked(adapter) matches generated(adapter) within 0.009
   on both tasks (R-G1 PASS)** with 0 illegal labels by construction. The
   L-G6 veto residual localized to the activation-dtype class (bf16 vs fp16;
   tokenization identical 0/908; all 91 argmax disagreements are the
   near-tied secret_path/no_grant pair). Numbers and non-claims:
   `bench/nursery/experiments/RESULTS-native-surface-2026-10-27.md`.
7. **The seed contract's enforcement — the client-side test now EXISTS**
   (2026-10-26): `test/mlx_native_seed_e2e_test.dart` asserts reproducibility
   through `MlxNativeTextClient`, the per-call meta echo, and the honesty
   warning. The counter-based sampler remains a core-side carrier (the
   native path decodes greedily; a seeded sampler is a feature, not a
   repair).
8. **The L-G6 cross-engine detail — LOCALIZED (2026-10-26): TWO native
   scorer bugs.** The stable logsumexp in `qwen_rank::position_logprobs`
   never added the max back (every native "logprob" carried `+max logit`;
   the eos "probability" was unnormalized and exceeded 1 on every row —
   the recorded 293/293 `eos_dominant_rows`), and `eos_dominates` compared
   a probability against a logprob (true always). Both fixed;
   `eos_dominant_rows` is now 0 and the corrected engines agree EXACTLY on
   perm (native 0.4403 == python 0.4403 == generation). veto retains a
   residual cross-engine delta (native 0.3128 vs python 0.2291 mean),
   recorded in
   `bench/nursery/experiments/RESULTS-tier-c-repairs-2026-10-26.md`; the
   FAIL verdict is invariant across every measurement of this line. The
   engine itself was never wrong — the 64-token parity gate held
   throughout; the scoring layer above it was.
9. **A CI gate.** This repository has no GitHub Actions workflow at all, so
   every number here is produced by a person, on a machine, on an evening.

### What else is possible (untaken, and ordered by what it can close)

1. **Rank, don't generate** (L-G6). Score the legal labels and take the
   argmax. This removes the "outside the label set" failure mode **BY
   CONSTRUCTION** — the failure class this lane has fought for three
   sessions — turns decode-bound evaluation into prefill-bound scoring, and
   changes the shared-vs-separate question from _what vocabulary did it
   emit_ into _which labels were candidates_. **If it matches the adapter,
   the LoRA line is not bought at all.**
2. **Prompt instead of training** (L-G1). Eight exemplars, two minutes, no
   adapter. If the base model with exemplars matches the adapter, the whole
   line was a formatting exercise.
3. **Train once, reuse forever.** The prompt is the cheap variable: every
   option-list, exemplar, answer-space and ranking question becomes a 2–5 min
   inference instead of an 18 min training arm.
4. **A permanent floor: the noise adapter.** A random-label adapter is the
   cheapest possible "emit a legal label" model. Every future arm should
   have to beat it, the way every future number has to beat the matched
   trivial baseline. The floor is built once and reused forever.
5. **Constrained decoding / logit masking.** Never tried. The cheap first
   measurement is the base model's _outside-label-set_ rate: if it is already
   ~0, masking buys nothing and the arm is dead on arrival; if it is not, a
   legal-label logit mask is a zero-training answer-space constraint that
   makes the shared-vs-perate question moot.
6. **Prompt-shape / prefix-cache uniformity** — the one DeepInfer idea with a
   product stake: a shared answer space is ONE instruction prefix, so it is
   cacheable across tasks. That is L-G5.
7. **Treat the model as a ranker over a closed vocabulary, not a text
   generator.** The answer space is an artifact of the _scoring_, not of the
   model. If the product needs a label, generating prose to be string-matched
   against a label set is a wasteful intermediate that costs accuracy (the
   leak), cost (decode), and a whole training programme (the adapter).

### The order, and why it is this order

**L-G1 and L-G6 run first, and either one of them can END the line on its
own.** Both are inference-only (2–5 min). A line that is closed needs no
noise arm, no third task, and no further training — so the two expensive
arms (L-G2 ≈ 18 min, L-G7 ≈ 1.5 h) are **conditional on the cheap ones
failing**. L-G4 and L-G5 are cost gates: they decide what the program rests
on and they decide nothing about whether the adapter is worth training.

### Non-claims

- Nothing in Row M changes the harness, the world, or the decision lane. The
  harness's permission gate is discharged by **Laya** (ADR 0084).
- No throughput number in this row is measured yet. `qwen_batch.rs` ships a
  **lockstep control** (each sequence keeps its own KV cache, so the weight
  read is _not_ amortized) and labels it as such: its ratio can never be
  mistaken for the gate number. A true fused batch needs a four-part change
  in `qwen.rs` (batch dim from `tokens.dim(0)`, cache allocated with it,
  per-sequence offset or pad+mask, and the tied embedding exposed) — the
  plan ops are already batch-capable; the plan _builder_ hardcodes `1`.
- The ranking arms (`qwen_rank.rs` native, `rank_labels.py` mlx-lm) are two
  implementations of one gate, and their defaults were aligned by hand
  (bare label, mean normalisation). They differ in engine and prompt shape;
  a deliberate cross-read is owed before either is read as the gate input.

---

### What is NOT bought, and why

- **A fused batched decode — yet.** L-G4 says the lever is **worth buying**
  (the projected whole-step amortization at batch 8 is **5.39×** against a 1.5
  gate) and that the four-part `qwen.rs` change is the price. The **bit-level**
  precondition cannot be met: a batched matmul on this box is **not**
  bit-identical to the same row alone (max abs diff 0.0625 in the body GEMM,
  0.0239 in the tied projection) and the **same-shape-class control diverges
  too**, so the batch dimension — not the `gemv`→`skinny_gemm` kernel switch
  — is what moves the bits. **But bit-identity was the wrong bar**: the
  product's own engine already compares the **DECISION exactly** with a 1e-3
  distribution tolerance, sized against a measured float16 re-rounding floor
  (3.6e-4) and a measured heterogeneous-batch **short-row defect** (0.86).
  **Not bought until the reformulated precondition holds** — the label does
  not move with the batch size, and the left-padded path carries no short-row
  defect. Evidence:
  `bench/nursery/experiments/RESULTS-acceleration-2026-10-21.md` §1.

- **An MTP attention head.** The cost structure is the killer; attention
  raises per-head cost without touching it (J'-G4).
- **More MTP acceptance arms on the current head.** It is invalid: in-sample
  0.90 vs held-out 0.12, and BELOW a trivial bigram baseline (0.148) — the
  arm measured a memorizing head, not a capacity limit.
- **A 4-bit dequant→merge→requant path.** No product consumer, no FFI
  surface, and the requantization error is the same order as the adapter
  delta (‖ΔW‖/‖W‖ median 5.0%) — it would void the measured capability.
  Refusing a quantized base at bind is correct, not merely conservative.
- **A rank / target-module sweep on the adapter.** K'-G1..K'-G4 must pass
  first; a shape sweep on an unmeasured base optimizes an unknown.
- **More adapter SHAPES before the conditioning question is answered.** The
  product-shape question ("one task-conditioned adapter per base" vs "a set
  of swappable specialists") is a different question from "which LoRA
  hyperparameters", and the first one decides whether the set surface is
  over-built.
- **A `Task:` tag as the conditioning mechanism.** K''-G1 fails: the tag's
  paired effect against the untagged control is not significant (perm
  p=0.185, veto p=1.000) and both point estimates are negative. The legal
  label set already in the prompt is the conditioning signal. **Not bought:
  a second, explicit signal.** (Unproven-harmful, not proven-harmful — at
  n=150 the control cannot resolve an effect below ~±0.06.)
- **A shared answer space across semantically dissimilar tasks.** Unproven
  and not yet even measurable: the only pair measured is two permission
  requests, where the leak is an UPPER BOUND. The per-task default stands
  until L-G7 says otherwise.
- **A Rust port of the numerical stack** (`numpy`/`scipy`/`pandas`, the
  trainer, the dataset generators). The scoring path imports no numpy and
  runs in 0.183 s; the GPU kernels are already Metal/C++ with Rust bindings.
  A port here buys no FLOPs and adds a second copy of the rules. The port
  law, and what IS worth porting, are in
  [`PYTHON-BOUNDARY.md`](PYTHON-BOUNDARY.md).

## The standing non-claims of this lane

- Every number here is **one machine, one model, one corpus, one seed, one
  held-out split** unless stated otherwise.
- Absolute tok/s and milliseconds are non-claims when the charge current is
  not real (POWER.md's charge-current hole); the **ratio** is the
  measurement.
- A gate pass is eligibility, never a product claim.
- Nothing in this lane changes the harness, the world, or the decision lane.
