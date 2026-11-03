# REASONING-TRACK.md — the reasoning gap: recorded attempts and directions (DEFERRED)

**Status: DEFERRED — a discussion seed for the owner, not a plan.** This file
contains NO gates and schedules NO arms. The lane's law is that a threshold
written before a run is a gate ([`MTP-GATES.md`](MTP-GATES.md) header);
nothing below is a threshold. When the owner picks a direction, it leaves
this file and becomes a pre-registered arm with its frozen gate in
[`MTP-GATES.md`](MTP-GATES.md) / [`TRAIN-GATES.md`](TRAIN-GATES.md) BEFORE
any run. Recorded 2026-10-28, branch `ag-c`.

> **Update 2026-11-03 (the arc completed):** the owner ran the replay
> critique to its end the same day. **Line IC-2** (Part 6) PASSED one
> pre-registered replicated cell — the content-specific procedure prefix on
> the 1.7B veto decider (+5.73 pp, p=2.4e-4, 13-0 one-way repairs; the
> random-prefix control did not replicate ⇒ content, not priming) — while
> model-selected intent proved harmful and **every preamble proved lethal to
> the adapter-served perm slot (−30 pp, p≈1e-23: the product law is never
> prepend lines to adapter-served decision slots)**. **Line SK** (Part 7,
> skeleton→fill on the deterministic decompression oracle — no rubric judge
> needed for that shape) closed F: a +8.89 pp trend, identical on both
> deciders, twice-blocked by its own frozen gates (underpowered at n=90;
> SK-G3's lexical carry criterion mismatched the entity rule), with the
> generic-structure control at exactly 0.00 pp. The intent-first question
> is now measured at judgment level AND constrained-generation level; what
> **RETIRED 2026-11-03 by owner decision**
> (RESULTS-HISTORY §21): no new arm from the intent-first family; the
> blind-rubric oracle and the powered SK rerun are declined, not parked.
> §18–§20; VERDICTS ✓/F rows; LINES Rows N–O.

> **Update 2026-11-03b (the owner named the goal):** the target is now
> explicit — reliable **world-data conversation on the local casts,
> including coding and tool usage** (the journal is the unbounded context;
> each turn is a bounded cut). The cross-repo program lives in the harness:
> `ecsai_harness/pkgs/xsoulspace_agentic_harness/docs/agent/local_actor_reliability_program.md`
> (that ROADMAP's immediate slice — everyday local collaboration — owns the
> live journeys). It consumes directions **#1** (completion@N loop-bench =
> the program's Phase 1; on owner go it leaves this file and freezes as
> MTP-GATES Part 8 BEFORE any run, per the law above), **#3**
> (decision-compile = ADVISORY measured-shape routing — routing economics,
> never an actor limit per the equals law, Phase 2b) and **#4**
> (verifier-gated draft loop = the gated-draft bench shape + Phase-3
> pilots). Receipt that sharpens direction #1: a local cast HAS completed
> the full durable tool lane once (qwen0.6B, proof driver, harness 090523e6,
> 2026-10-30) — n=1 is exactly why the loop, not the shot, is the
> unmeasured quantity. Still no gates in this file.

## Why this file exists

The lane converged on two live, measured tracks: a **capability track**
(generative work — Qwen3-0.6B + one shared untagged LoRA adapter, consumed
as a ranker over a closed vocabulary; the ✓ rows in [`VERDICTS.md`](VERDICTS.md))
and a **decision track** (laya + the perm decision head; [`ROADMAP.md`](ROADMAP.md) §1).
Neither provides **reasoning**: multi-step deliberation on open-form work —
what "thinking mode" names. Every recorded attempt to have it on the local
casts is negative, and no direction for closing the gap was ever written
down in the repo. This file is that record, deferred to discussion.

## What was already tried (the recorded attempts, non-coding)

| attempt | measured result | class | evidence |
| ------- | --------------- | ----- | -------- |
| Thinking mode at 0.6B (qwen, `enable_thinking=true`) | 2/1/0 on the scorecard — **hurts** at this scale | F (reopen: a bigger trunk = a NEW registered arm) | fair matrix; [`RESULTS-HISTORY.md`](RESULTS-HISTORY.md) §2 |
| Thinking at 2.6B (LFM2.5-2.6B: think-open template variant, answer cut at the model's own `</think>`, budget law `max(5×cap, 384)`) | served correctly, scored **under the 1.2B on every lane** at 19–33 tok/s with 8–33 s thinking walls — NOT adopted | F | ADR 0058; [`VERDICTS.md`](VERDICTS.md) F table |
| Ungated drafting (16-block nap-draft, LFM2.5-1.2B, 2026-10-08) | drafting **fails faithfulness** — the loop generated blocks that did not hold to the source | F | local-text-model lane session record (harness-side python `mlx_local` era; not in this package's tracked tables — carried here so it is not re-run) |
| Self-draft speculation | failed faithfulness; draft-MODEL speculation only considered at ≥4:1, and unprofitable when measured (0.42–0.75×) | F / C | ADR 0056 verdicts; [`RESULTS-HISTORY.md`](RESULTS-HISTORY.md) §3 rows A/A′ |

The serving machinery for thinking EXISTS and is product-grade — the
request-level `thinking` switch in core's `GenerationOptions` (hosted
providers map it to their reasoning controls; casts without one answer with
an honest echo), `serve_text --thinking`, the think-open template variant,
`</think>` answer cutting, the thinking budget law. What does not exist is a
local cast where turning it on helps.

Adjacent and often confused with reasoning, already closed for OTHER
reasons: MTP (physics: `body(8)/body(1)` = 2.0–3.5) and draft-model
speculative decode (economics). Both are SPEED techniques; neither was ever
a reasoning result, and neither reopens this question.

## The prior analysis this file carries into the repo

2026-10-10 reliability analysis (delivered as analysis only in session,
never committed until now): the thesis that **reliability is a property of
the QUESTION'S SHAPE and loop honesty, not model scale** — the same
LFM2.5-1.2B scores 16/16 on finite-choice decisions, 5/5 tools, 8–9/10
decomposition, 6–7/10 open chat, 2–3/5 free-form SWE: a **5× spread from
shaping alone** (the lane's own scorecards, ADR 0057-era records). Its
proposed four-loop architecture:

0. **reflex** — a mechanical tier that only answers reflex-shaped questions
   (it cannot hallucinate because it never answers anything else);
1. **decision** — COMPILE control flow into finite-choice questions (next
   move, ranking, retry-or-escalate) = laya's track, the biggest measured
   win — it moves work into the 16/16 cell;
2. **draft** — the small model proposes DATA, never state change, and only
   in measured-good cells;
3. **deliberation** — the only mutating loop: claim → bounded cut → draft →
   materialize → deterministic check → keep/revert/escalate, ledgered
   predicted-vs-observed (the ADR 0032 protocol).

Its five-phase program: (A) a **loop-bench** — measure completion@N (the
lane has only ever measured SHOT reliability; a 2/5 one-shot inside a
keep-if-verified loop is a different measurable quantity and has never been
measured here); (B) a decision-compiler sweep; (C) a verify-or-discard
ratchet runner; (D) the reflex tier; (E) ONE program file binding metric,
budget, frozen oracles and the escalation ladder — the scattered equivalents
(palette, consent plans, D8 `--check`, frozen oracles) exist but were never
bound as one program.

## Directions on the table (for discussion; none scheduled)

Ordered by how much of the lane's own confirmed machinery they reuse:

1. **Measure the loop, not the shot (completion@N + keep-if-verified).** The
   cheapest genuinely-new measurement, and the one the analysis names
   first: on lanes that HAVE frozen oracles, run the arm that has never run.
   The fused batch (1.93× @ B8) makes N-candidate generation cheap; the
   ranker shape is the lane's strongest confirmed verifier for closed
   vocabularies; the replay infrastructure (gate questions answered from
   cached completions at ~0.2 s, no GPU) extends naturally.
2. **Deliberation as selection, not generation.** Generate N candidates
   (batched), select with a verifier instead of trusting one greedy pass —
   the confirmed ranker result (ranked == generated within 0.009, zero
   illegal labels by construction) extended from labels to candidate
   answers. The open question is the VERIFIER for open-form answers:
   deterministic checkers exist for code, not for conversation (honest
   boundary below).
3. **Decision-compile more reasoning-shaped work.** The measured biggest
   win: move work out of open generation into finite-choice questions (the
   decision track's existing shape; decomposition at 8–9/10 on 1.2B is the
   measured good cell to build on). This is "reasoning without generation":
   decompose → decide → act, with the adapter/ranker serving each step.
4. **Draft loop, verifier-gated only.** Drafting failed UNGATED; the
   four-loop design constrains drafts to proposed data with a keep/revert
   gate. Re-ask only with the gate in place, in measured-good cells, never
   free-form.
5. **The hosted escape hatch (interim product answer).** The contract
   already carries a request-level `thinking` switch that maps to hosted
   providers' reasoning controls, and the routing layer already reorders
   peer-before-local under pressure: reasoning-shaped requests can go to a
   hosted reasoning model while the local stack serves capability +
   decision. This buys reasoning NOW at the cost of the local-only
   property, and needs a routing policy decision, not a training arm.
6. **The reflex tier (long shot).** The althea SSM mechanical tier —
   outside this repo's control; revisit only if that project lands a
   wireable tier.
7. **Weight-space programming (frontier-LLM weight repair of a local
   cast) — EXTERNAL POINTER, recorded 2026-11-03; unreplicated here.**
   Measured externally (Takehi et al.; blog + full logs + HF checkpoint):
   GPT-6 Astra edited Qwen3.5-0.8B weights directly — no gradients, no
   training; a CPU python kernel over the weights plus a forward-pass
   budget (50 passes; each answers ≤512 problems / reads ≤1024 texts);
   it diagnoses failure patterns from OUTPUTS, traces them to weight
   directions, subtracts. MATH-500 7.9→48.1, GSM8K 13.8→67.1, **IFEval
   21.0→62.3**, hit-token-limit 93→33.1; 0.016 % of weights changed (a
   "looping direction written by MLPs in layers 15 and 19"). The
   authors' own limits: it CANNOT add an absent capability (Gemma 270M
   moved ≈±1 point), weights-only reading fails at scale (needed
   attention patterns), budgets below ~50 passes barely moved the loops,
   and no benchmark/harness is released yet ("currently building").
   Why it is relevant here: the dominant local-cast loss class is
   INSTRUCTION FOLLOWING (malformed action envelopes, format-bound
   scoring, no-effect/looping rounds — reliability-program receipts
   U2/U4), and the artifact is a LOCAL checkpoint: pay hosted once, run
   local forever — zero marginal cost, which is what the harness's
   unlimited-actor architecture needs.
   Laws it must face BEFORE it could become an arm: (a) the 2026-10-28
   synthesis "no distillation from qwen anywhere" — this is NOT
   distillation mechanically (no data generation, no gradients) but it
   IS a hosted→local capability transfer; it needs an explicit owner
   decision as a NEW line; (b) the K-G4 requant law (requant error ≈ the
   adapter delta): an edit changing 0.016 % of weights must be shown to
   SURVIVE 4-bit requantization, or run at fp16 (0.6B fp16 fits the
   16 GB machine easily) — retention is a first-class cell; (c) the
   standard pre-registration: same frozen corpora/scorers, edited vs
   unedited, McNemar pairing, trivial-baseline law; (d) sequencing —
   only AFTER the loop-bench (program Phase 1) provides per-shape
   pass@N baselines, else an edit win cannot be separated from noise.
   Cheapest meaningful pilot: qwen0.6B, a corpus assembled from the
   lane's OWN malformed-envelope / no-effect receipts + the tool-lane
   fixtures; success = the instruction-following rate on the frozen
   fixtures with the edited weights surviving requant.
   Source: x.com/rikiyatakehi/status/2117313742891327994 →
   rikIyat.github.io/blog/weight-space-programming (logs:
   github.com/RikiyaT/lm_understand-logs; HF:
   RikiyaT/Qwen3.5-0.8B-weight-space-programming). NON-CLAIMS: external
   results unreplicated here; one lab, pre-benchmark; their largest
   edited LLM is 0.8B; the edit session depends on a hosted frontier
   model even though the artifact does not.

## Honest boundaries (carried from the analysis, unchanged)

- **No deterministic checker ⇒ N retries buy nothing on soft quality.** A
  1.2B-class model does not get "extremely reliable" on open chat by
  looping; the loop honest options are escalate or declare softness.
- **Context assembly for small windows** — the 2026-10-10 boundary
  ("UNSOLVED": the measured afm profile dropped every decision at 2776
  tokens; the coding cut needed 4187+) is STALE as an absence claim
  (annotated 2026-11-03): the harness has since landed the model-aware
  capacity chain — casts declare real windows, session tiers size
  `maxInput`, the input gate names the dominant term and runs one bounded
  retry with a floor short-circuit (2026-10-20..11-02; harness
  `surface_gaps.md` "compaction rule" entry — the 2776 measurement
  predates the chain and its diagnosed cause was a WRONG WINDOW +
  UNBOUND MODEL). What remains is live re-measurement debt (reliability
  program Phase 0), not absence.
- Thinking at 0.6B, the 2.6B cast, self-drafting, and ungated drafting stay
  **measured-dead**; reopening any of them is a NEW registered arm with a
  frozen threshold, not a rerun.

## Non-claims

- This file records direction, not feasibility: no direction above has a
  measured gate, a cost, or an owner decision.
- The 2026-10-10 analysis enters the repo for the first time here; its
  numbers cite the lane's own scorecards. The drafting-faithfulness result
  cites the local-text-model lane's session record, not a tracked artifact.
- Nothing here changes the harness, the world, the frozen gates, or the
  open queue in [`ROADMAP.md`](ROADMAP.md).
