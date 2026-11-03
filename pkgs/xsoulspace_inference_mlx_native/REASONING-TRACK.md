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
> remains owed and unscheduled: the blind-rubric oracle for open-form
> quality, and a properly powered SK rerun (≈350+ cases, non-lexical carry
> criterion) if the owner wants the trend resolved. §18–§20; VERDICTS ✓/F
> rows; LINES Rows N–O.

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

## Honest boundaries (carried from the analysis, unchanged)

- **No deterministic checker ⇒ N retries buy nothing on soft quality.** A
  1.2B-class model does not get "extremely reliable" on open chat by
  looping; the loop honest options are escalate or declare softness.
- **Context assembly for small windows is UNSOLVED** (the measured afm
  profile dropped every decision at 2776 tokens; the coding cut needed
  4187+) — meaning-runtime cuts must become model-aware before any
  multi-step loop is cheap.
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
