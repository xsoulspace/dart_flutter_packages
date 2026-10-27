# ROADMAP — the adapter/acceleration lane (mlx_native)

**This file is the single entry point for "what is closed and what is open"
in the MTP/LoRA/acceleration lane.** The registers it distills:

- [`VERDICTS.md`](VERDICTS.md) — the full verdict tables (F/C/O/V/✓), the
  contract for what each verdict class may claim.
- [`LINES.md`](LINES.md) — the per-line ledger (Rows A..M) with evidence.
- [`MTP-GATES.md`](MTP-GATES.md) — the frozen gates (nothing here moves one).
- [`EXPERIMENT-PLAN.md`](EXPERIMENT-PLAN.md) — the cost model and the plan.

A closed experiment lives ONCE, here, with its verdict and its evidence
pointer. A ledger row is not re-argued because a newer document summarized it
differently; when documents disagree, the cited artifact wins.

---

## CLOSED EXPERIMENTS (extracted — verdict, why, evidence)

### The adapter line (Rows K/K'/M): DECIDED — the adapter is load-bearing

| experiment | verdict | the measured why | evidence |
| ---------- | ------- | ---------------- | -------- |
| Adapter capability | **CONFIRMED** | +0.31 perm / +0.47 veto over matched trivial, coverage 1.0, strict scoring | `LINES.md` Rows K/M |
| The `Task:` tag as the mechanism (K''-G1) | **FAIL** | paired vs untagged: perm Δ −0.053 (p=0.185), veto Δ −0.007 (p=1.0) | `MTP-GATES.md` Part 3 |
| A SET of per-task swappable adapters | **FAIL** | single-task adapter damages the other task below trivial (0.1733 vs 0.2733, p<0.001) — interference is the unconditional prior | `LINES.md` Row K |
| Format-only explanation (L-G2 noise control) | **MISS** | random-label adapter: 0.5392/0.2511 vs thresholds 0.7737/0.6533; veto collapses to one majority label | `RESULTS-noise-2026-10-26.md` |
| Few-shot control (L-G1) | **FAIL** | 8 exemplars buy +0.03/+0.05 vs the adapter's +0.31/+0.47 | `LINES.md` Row M |
| Constrained ranking of the BASE's labels (L-G6) | **FAIL** | ranked(base) == base on perm — a DECISION failure; the base ranks, wrongly. Two native scorer bugs found and fixed en route (stable-lse max add-back; probability-vs-logprob eos) | `RESULTS-tier-c-repairs-2026-10-26.md` |
| Third, dissimilar task (L-G7) | **PASS** | shared 1.0000 = untagged 1.0000 on the third cell, leak 0, completions 204/204 identical; shared still costs −0.089 on the close pair's perm cell | `RESULTS-third-2026-10-26.md` |
| Shared answer space, cost (L-G5) | **FAIL cold, recovered warm** | +22 tok/request, +55 % cold prefill wall; at a 2048+-token shared prefix a warm pool serves 100 % hits (32–43 ms vs ~1880 ms) | `RESULTS-fused-tier-a-2026-10-26.md` §L-G5 |
| Arm determinism | **MEASURED: NOT run-deterministic** | two identical runs: distinct adapter sha256s; score band ±0.05–0.11; L-G2's MISS stable | `RESULTS-tier-c-repairs-2026-10-26.md` §1 |
| Seed contract E2E | **CLOSED** | `test/mlx_native_seed_e2e_test.dart` pins reproducibility, meta echo, honesty warning | Tier C |

### The acceleration program (Row M / Tier A): the levers are bought

| experiment | verdict | the measured why | evidence |
| ---------- | ------- | ---------------- | -------- |
| MTP as speed (Line J) | **CLOSED on physics** | body(8)/body(1) = 2.0–3.5 vs the 1.50 NOT-FLAT gate; no MTP arm is bought at any acceptance | `LINES.md` Row J |
| Fused batched decode (Tier A) | **BUILT, GATED, MEASURED** | labels exact across solo/B8/B16; co-batch invariance 0.0; solo-join floor 0.071 vs defect control 0.60; **1.93× @ B8, 3.19× @ B16**; the 5.39× projection retired | `RESULTS-fused-tier-a-2026-10-26.md` |
| Fused rank economics | **CONDITIONAL** | 0.80× of sequential at K=4 (prefix-once + cache fan-out), 1.03× at K=2 | same |
| Bit-identity as the batch precondition | **RETIRED** | the batch dim moves the bits; the standing bar is decision-level invariance + no short-row defect | `MTP-GATES.md` Part 4 post-run note |
| Prefix-cache weight identity (Row L) | **LANDED** | engine-owned digest; stale entries dropped; test-locked | `qwen.rs::weight_identity` |

### The mechanism lines that closed earlier

| experiment | verdict | why (one line) | evidence |
| ---------- | ------- | -------------- | -------- |
| Draft-model speculative decode | **CONDITIONAL-FAIL** | 0.42–0.75× native at 1:2.8; needs ≥4:1 pairing | spec-decode record |
| Emergent MoE route persistence (Line I) | **FAIL** | plateaued ~0.34; only window>1 passes by construction | `TRAIN-GATES.md` |
| Paged-MoE expert store on 16 GB (Line B) | **FAIL** | 42.5 % hit rate → 0.33 tok/s, I/O-bound | `stage1_paged_moe/RESULTS.md` |
| Route-ahead prefetch (Line C) | **FAIL** | 0.4 % route persistence — no locality to prefetch | `bench/LINES_PLAN.md` |
| Device mesh M1/phones (Line F) | **CONDITIONAL** | needs ~50× bytes/token drop | `bench/LINES_PLAN.md` |
| `LAYA_COMPILE` default | **CONDITIONAL** | 6.6 s first trace; daemon-class workloads only | R6 record |
| LFM2.5-2.6B as production cast | **FAIL** | under the 1.2B on every lane at 19–33 tok/s | ADR 0058 evidence |

---

## THE OPEN ROADMAP (ordered by what it can unlock)

1. **Nursery RUNG-1 (PERM-GATE-1) — attempts 5–6 RAN 2026-10-27; the
   42.8M dense line CLOSED WITH DATA; the rung stays open at its named
   design levers.** The acceptance harness
   (`tool/nursery/slots/perm_gate_1/`) was fully exercised with two
   pre-registered attempts (predictions written before training, the
   margin decision rule and its TAU-selection rule frozen on the corpus
   eval split before any frozen case was scored):
   - **Attempt 5 (dense-perm-c)** — corpus v3 (v2 + a 600-row granted-
     veto slice + a 500-row granted-safe slice, law unchanged, frozen-
     case disjoint) + warm start from attempt 4 at lr 5e-4, plus the
     margin rule (`allow_once` iff margin > TAU; TAU=0 is attempt 2's
     argmax). **0.667 agreement, ZERO unsafe** — the margin mechanism
     solved the safety failure (3 → 0) but no frozen case's allow-margin
     cleared TAU=2.0, so the candidate degenerated to all-abstain.
   - **Attempt 6 (dense-perm-d)** — from scratch, attempt 4's recipe on
     v3, 1700 steps. **0.667 / 0 unsafe at TAU=1.75; eval argmax 0.6021**
     — under the pre-registered 0.75 line bar: the 42.8M dense line
     closes. Its measured ceiling: attempt 4's **0.722 (argmax, 3
     unsafe)**; the safety/agreement frontier is mapped — 0 unsafe via
     calibration costs agreement down to baseline.
   - Standing shipped behavior unchanged: ALL-ABSTAIN (0.667 / 0 unsafe)
     — still the best zero-unsafe operating point and the live data
     collector. Fixtures: `dense-perm-c/` + `dense-perm-d/` RUN-RECORDs
     (prediction/observed, margin sweeps, verdicts), corpus v3 manifest
     (3000 rows, 0 frozen-case collisions).
   - **Re-scoped next levers (design changes, not more arms on this
     recipe):** a bigger trunk toward the 50M top of the Rung-1 band; a
     slot-head MLP readout over stepwise states (never tried on the
     dense trunk); a curriculum over veto-hardness; real labeled
     examples from live all-abstain escalations. Live-slot half of
     RUNG-1 acceptance (the real permission_gate.v1 answer quality)
     remains a separate, later record — never assumed.
2. **A CI gate — LIVE AND GREEN at its clean-clone truth (2026-10-27;
   first run 40486026348 named the blockers, re-scoped run 40486871329
   PASSED, `native-compile` 30 s).** `.github/workflows/mlx_native_gate.yml` — the file MOVED
   from `.github/archite_workflows/` (which GitHub Actions never reads; it
   had never triggered a single run — paid-for lesson recorded in the file
   header), now triggering on pushes to main/master AND `ag-c`. The first
   real run named TWO blockers, both pre-existing repo conditions:
   (a) the DART leg cannot run on a clean clone at all — the workspace
   root's dependency_overrides point whole package families at machine-
   private checkouts (absolute `/Users/antonio/...` paths), so `pub get`
   fails for every workspace package; publishing or vendoring them is an
   OWNER decision. Until then `flutter test` is local-only (green here:
   42 pass / 1 skip / 0 fail).
   (b) `cargo test` needs the machine-local cmake-built MLX/mlxc static
   libraries (build.rs refuses loudly without them) — the REAL test gate
   stays local on AC; CI runs the honest compile gate
   (`cargo check --release --all-targets` against named stub dirs).
   The former local red ("request-level thinking") is DISPOSED: budget
   128 → 768 with the assertion set unchanged — full local battery 42
   pass / 1 honest skip / 0 fail.

### Closed 2026-10-27, later the same day (was open this morning)

- **Tracked fixture for the adapter-format gate** (EXPERIMENT-PLAN §5.3):
  `tests/mlx_lm_artifact_merge.rs` gained a second gate,
  `the_artifact_format_gate_runs_anywhere_on_a_tracked_synthetic_adapter`
  — a synthetic mlx-lm safetensors built IN-TEST with known dyadic values
  at the TRUE on-disk orientation (`lora_a` [in,r] / `lora_b` [r,out]),
  so every clone with a Metal device runs the full reader law: load_auto
  detection, the transpose verified by VALUE (an orientation error flips
  the expected numbers), the exact merge delta `1 + scale·B@A` per pair,
  full `apply_to`, the missing-target refusal, the unmatched-`lora_a`
  refusal, and the no-LoRA-tensors refusal. The trained-artifact gate
  still proves the trainer's bytes where `bench/` exists and still skips
  loudly elsewhere. Both gates green locally (2/2).

### Closed 2026-10-27, earlier the same day (was open this morning)

- **Product wiring of the fused batch (Tier A at the wire)** — LANDED and
  GATED: `mlx_native_qwen_generate_batched` FFI (+ api-version probe,
  older dylibs degrade to solo), `NativeQwenTextEngine.generateBatch/
  generateBatchAsync`, and an OPT-IN coalescing window in
  `LayaQwenChatServer` (null window = the wire is byte-identical to the
  pre-change solo path; window on = concurrent requests within it are
  served as ONE fused batch, size-1 windows route solo, failed batches
  fall back per-row, counted). **W-G1/G2/G3 all PASS on the first run**
  (six heterogeneous classification answers byte-equal solo at the wire;
  the batch actually formed, zero fallback; a lone request untouched) —
  bars frozen before the run in
  `bench/nursery/experiments/RESULTS-wire-batch-2026-10-27.md`. Free-form
  streams keep the engine gate's recorded tie-flip freedom (agreement
  reported, never gated) — which is WHY the window is opt-in; flipping
  the product default is an owner decision this evidence now informs.
  Gate: `test/mlx_native_qwen_batch_wire_test.dart`.

### Closed 2026-10-27 (was open when this file was created)

- **The native-surface capability number** (the last owed Tier-C repair,
  V-r): `Qwen3::attach_lora` — runtime LoRA on the 4-bit base, the
  no-confound mirror of the python path. **N-G1: PASS perm (0.8976, native
  ABOVE python's 0.8737) / FAIL veto (0.6828, −0.02 beyond the margin)** at
  the frozen bars; coverage 1.0, leak 0, +0.3379/+0.4009 over matched
  trivial. The V-r row is closed: the number exists on the shipping surface
  and says "carries on perm, short on veto". Gate:
  `tests/qwen_runtime_lora.rs` (attach/refuse/logits-move/in-set/rank);
  readings: `bench/nursery/experiments/RESULTS-native-surface-2026-10-27.md`.
- **ranked(adapter) (Tier B-5)**: **R-G1 PASS both tasks** — ranked matches
  generated within 0.009 under the adapter, 0 illegal labels by
  construction, 0.71× generation cost on perm even on the imperative path.
  The "model as ranker over a closed vocabulary" product shape is
  measured-viable.
- **The L-G6 veto residual** (became a gate input today): LOCALIZED —
  tokenization identical (0/908), scoring math identical, per-label sums
  differ median 0.27 nats (the bf16-vs-fp16 activation-dtype class), and
  mean normalization turns that band into argmax flips on exactly the
  near-tied `secret_path`/`no_grant` pair (all 91 disagreements). Verdict
  invariant. Sum-norm is the engine-robust normalization (80 % agreement).

### Deliberately NOT scheduled (and why)

| item | why |
| ---- | --- |
| Any MTP-shaped arm on this hardware | Line J closed on physics; new hardware requires a NEW registered arm |
| More mechanism arms (tag, option list, task count) | the attribution is measured at both ends; re-running it is not a new question |
| The veto residual as a standalone cleanup | not a gate input until ranked(adapter) makes it one (it now has) |
| 4-bit dequant→merge→requant | no consumer; requant error ≈ the adapter delta (K-G4) |
