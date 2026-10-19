# TRAIN-GATES.md — the training gates for the un-VM nursery (Line I)

One screen. Read this before training any nursery model (rung 0 and up).
Full design context: `bench/stage0_diffusion_probe/FINDINGS-AND-DISCUSSION.md`
§12–13 (Line I), `bench/LINES_PLAN.md`. Gates are frozen here, before the
first training run, exactly like POWER.md freezes the power laws: a
threshold changes only by editing this file **before** the rung's first
training run — never after seeing results.

## The four gates

| Gate | What it freezes | Metric (frozen) | Threshold |
|---|---|---|---|
| GATE-1 | pole legibility | Fraction of poles whose activation separates the label classes: max pairwise Cohen's d ≥ 1.0 on the labeled probe set | per-rung config; **rung-0 ≥ 0.60 — set FINAL 2026-10-18 by operator instruction, before the first RUNG-0 run** |
| GATE-2 | route persistence, **by training** | One-step expert-set equality on held-out traces (stage1 `routes.jsonl` row format `{pos, layer, experts}`) | **≥ 0.70 — frozen** (inherited from Line C's gate) |
| GATE-3 | label-vs-behavior agreement | Agreement of the model's predicted labels with the deterministic teacher (`ecsly_context` `segmentText`) on held-out clause data | per-rung config; **rung-0 ≥ 0.90 — set FINAL 2026-10-18 by operator instruction, before the first RUNG-0 run** |
| GATE-4 | payload fits the back room | Shape math from the packed store manifest: total bytes AND bytes/token (Σ over MoE layers of top-k × mean expert bytes) | payload ≤ back room (10 GB desktop class) AND bytes/token ≤ rung target (rung-3: ≤ 25 MB/token) — frozen with the rung table |

### Reading a sub-0.70 GATE-2 (pre-registered 2026-10-18, BEFORE the first RUNG-0 run)

0.70 was Line C's prefetch-usefulness bar, not the un-VM thesis itself. The
thesis GATE-2 tests is narrower: **route persistence can be manufactured by
training where pretraining did not leave it** (30B measured 0.4%, flat
across layers). Therefore every RUNG-0 run records, beside the set-equality
number, the per-layer top-1/top-2 router-gap distribution
(`traces/margins.json`: min/p50/p95, and the fraction of gaps ≥
`router_margin_target`) — and the verdict is read as:

- **G2 ≥ 0.70** → persistence trained in; the weight-language thesis holds
  at drosophila scale; proceed to RUNG-1 via PERM-GATE-1 (laya's real
  slot).
- **G2 < 0.70** → record the NO with the traces — the persistence thesis
  closes with data at this scale — AND read the margins: if p95 gap ≥
  `router_margin_target`, routing is noise-stable (un-flippable by
  quantization noise, the PORTING-MOE requirement) even though it is not
  temporally persistent, and the decision head is unaffected: RUNG-1's
  slot acceptance (PERM-GATE-1) never needed routing, and the `label_head`
  stands alone. The nursery's deliverable (a decision head for laya's
  real slot) does not depend on GATE-2 passing; only the MoE-as-language
  thesis does.

Standing decision (2026-10-18): **no rung-3 engineering — route plans,
gather-GEMM, custom kernels — is built until a candidate passes GATE-2.**
Rung-0 problems do not buy rung-3 tools.

**Reading GATE-2 passes honestly: construction is not emergence
(2026-10-18, after the routing_window A/B).** The standstill above is
lifted by a candidate whose persistence is BY CONSTRUCTION
(`routing_window = 128`: set-equality 0.9996, GATE-3 0.860 and eval CE
3.337 vs control 0.851 / 3.451 — capability intact, GATE-1 poles 19/32).
That is a real pass of the written gate and a real green light for route
plans — a plan needs the route known W tokens ahead, and windowing
provides exactly that. It is NOT a win for the trained-persistence
thesis: emergent persistence under per-token routing plateaued at ~0.34
at two scales (3.5M, 43M) and never approached 0.70. Future readers:
`GATE-2 PASS` on a `routing_window > 1` candidate means the schedule is
prescribed, not learned; the MoE-as-language question stays closed
unless a per-token-routed candidate passes.

### GATE-1 pole definition v2 (amended 2026-10-18, AFTER the first RUNG-0 verdict — with the measured reason)

The first RUNG-0 run measured v1's DEGENERATION, not just its failure: the
margin hinge saturates softmax combine weights into one-hot selections, so
v1's pole value (mean combine weight per expert per example) collapses to
a selection frequency and washes out class signal (23/32 poles legible at
init → 4/32 after training, while routing itself got MORE structured —
margins p50 7–16). v1's verdict stands in history as measured. v2 moves
the pole to the pre-softmax router logit: pole value = MEAN ROUTER LOGIT
of (layer, expert) over the example's positions — every expert has a logit
at every position, so nothing depends on being selected, and the graded
signal survives saturation. Same metric law (max pairwise Cohen's d ≥ 1.0
on the labeled probe set), same rung-0 target 0.60, same oracle. This
amendment exists because the metric was measured degenerate, not because
its threshold failed; threshold-shopping it is not — the re-audit runs on
the SAME checkpoint whose v1 verdict is recorded.

### The routing_window A/B (pre-registered 2026-10-18, BEFORE the first windowed arm)

The one fair last test of the persistence thesis. A candidate trains with
`routing_window = W > 1` (one expert SET per W positions, re-decided at
each window start; `routing_window = 1` is the per-token control). GATE-2
under W > 1 is forced persistence — set-equality is bounded below by
(W−1)/W by construction — so **GATE-2 is not the A/B's endpoint**; it is
recorded for the traces. The endpoints are capability at matched compute:

- **LM loss** (final eval CE) and **GATE-3 agreement** of the W-arm vs a
  fresh `W=1` control at identical seed, data, steps, and batch.
- Decision rule (set before any arm ran): if the best W-arm holds GATE-3
  within 0.03 absolute AND eval LM loss within +5% relative of the W=1
  control, persistence-by-construction is not where capability dies, and
  the route-plan line keeps one live research question. If capability
  degrades beyond either bound, the persistence thesis closes with data:
  forced persistence costs the model, and no rung-3 route work revives it.
- GATE-1 (pole v2) and margins are recorded per arm, read as evidence
  about WHERE the router's signal went, not as the A/B verdict.

### GATE-1 v2 probe re-target: residual-stream directions (added 2026-10-18 to the standing launch checklist)

The pole v2 re-audit found the router's graded signal did not separate
classes (2/64 at scale) while the label head reads ~0.83 from the residual
stream — the signal, wherever it is, is not in expert selection. Every
future rung's launch checklist therefore includes: run
`tool/nursery/gates/probe_residual.py` on the exported checkpoint —
per-kind Cohen's d of the normalized residual stream at the label position
(k vs rest, along the mean-difference direction), plus nearest-centroid
accuracy. Recording tool, not a gate: any pass/fail threshold for it must
be written here, set final, BEFORE that rung's first training run.

## Oracle laws (what makes a gate a gate)


1. **Gates never self-grade.** A gate reporter reads recorded evidence
   (activations, traces, predictions, manifests) and computes the verdict;
   the training loop cannot pass a gate by assertion. Gate inputs carry
   sha256 stamps into the emitted verdict.
2. **Every gate ships a deterministic self-test oracle** (`--self-test`)
   with pinned PASS and FAIL synthetic cases. A gate whose self-test does
   not pass may not be run on a real candidate.
3. **Correctness gates are never power-conditioned** (same law as parity:
   they must trip anywhere, anytime). GATE-4 is shape math from a manifest —
   no timed measurement, so the power law does not reach it. Any tok/s or
   wall-clock number stays under POWER.md: recorded with real charge current
   (see the charge-current hole), never a gate input at rungs 0–2.
4. **The teacher is canonical, never re-implemented.** GATE-3's labels come
   from the deterministic `segmentText` marker tables (imported, not
   copied). A candidate may only be compared against held-out labels.
5. **A gate failure is a recorded verdict, not a shame** — the number
   re-scopes the next rung (the Line-B pattern: verdict with data).

## Rung table (thresholds bind per rung)

| Rung | Scale | Slot | Extra binding gate |
|---|---|---|---|
| RUNG-0 | 1–5M drosophila | the audit organism | all of GATE-1..4 on every checkpoint; no scaling until they pass |
| RUNG-1 | 15–50M decision head | laya's real slots | acceptance = PERM-GATE-1 (`tool/nursery/slots/perm_gate_1/`) — real daily job, not a fixture |
| RUNG-2 | 100–300M beat writer | text-derived beats only | provenance-stamped, forgettable, never in the read path (standing law) |
| RUNG-3 | 0.5–1B pamphlet | generative ~100 tok/s class | full un-VM engine test: route plans, gather-GEMM, packed-from-birth store, ≤ 25 MB/token |

## Non-claims

- Gates passing does not claim capability — acceptance for RUNG-1 is
  PERM-GATE-1 on the real decision slot, and daily use is the only
  usefulness claim.
- "Route persistence ≥ 0.70 by training" is the research hypothesis Line I
  exists to test; the gate measures it, it does not presume it. A measured
  persistence ceiling (with traces) re-scopes C and F with data.
- GATE-1/3 provisional thresholds are provisional until written final here;
  that edit is part of a rung's launch checklist, not a post-hoc knob.
