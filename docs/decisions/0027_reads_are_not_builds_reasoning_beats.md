# ADR 0027 — Reads are not builds: reasoning beats and the decision-classified mover

- Status: Accepted
- Date: 2026-09-06
- North Star impact: `clarifies` — applies the existing laws (zoom-not-read
  ADR 0023, budgets ADR 0009, canonical rows ADR 0021, measurement ADR 0016)
  to the dogfood hot path: pi↔harnessd gate latency. No new vocabulary; two
  new wire fields (additive) and one prompt-router classification.
- Builds on: [0023](0023_filesystem_projection_target_edit_as_rederivation.md),
  [0024](0024_filesystem_one_map_graph_typed_materializers.md),
  [0025](0025_host_layer_extraction_composable_embedding.md),
  [0026](0026_workspace_domain_specs_as_data_wire_codec.md)

## Context

Measured pi gate runs (remote-mover, glm-5.3-flash via Parasail) spend
~2.5–4.5 min per phase. Decomposition of where the time goes:

1. **Model latency × decision count** — every daemon decision is a full
   `propose_move` round-trip; the mover is a thinking model (~5–25s per
   call) with NO decision classification: a mechanical `[scan]` costs the
   same as a decomposition.
2. **`dart test` grading on reads** — the daemon turns EVERY prompt into a
   run-graded task (`taskFromSentence` → unconditional final gate), so a
   read-only directive (`[scan]`, `[zoom]`) pays a ~20–40s cold
   pub-resolve + compile. Measured: a decision with zero moves showed
   `wall 68775 ms` — the grade dominated.
3. Daemon cold start when the extension cannot attach (fresh temp
   workspaces per gate).
4. Upstream flakiness retries (pi-side, tunable).
5. Two phases per gate, sequential.

Structural reading: **the daemon routes reads through the graded-task
surface.** ADR 0023 already demoted reads — `meaning_zoom` IS the read;
a zoom cut is the ANSWER, not a build step. Routing it through a build
oracle is a category error, and it is also the single biggest latency item.

Separately: **model reasoning has no first-class treatment.** The mover's
thinking is invisible to the daemon (unmeasured), can silently rot into
context if re-projected, and arrives unclassified on refusals (measured
failure: the mover read adversarial fixture text as an injection warning
and returned an empty move — a silent bounce with no named failure class).

## Decision

1. **Reads are not builds (prompt router).** `HarnessAcpBackend.prompt()`
   classifies the prompt BEFORE task creation:
   - **Directive-only read prompts** (`[scan]`, `[zoom …]`, structured
     `harness_zoom`/`harness_impact` payloads, no mutation payloads) are
     executed DIRECTLY against the session's registry (mechanical host
     program — zero model, zero grade) and the cuts stream back. No task.
   - **Free-form read-ish delegations** (real model decides what to zoom)
     run as `readOnly: true` tasks: the actor loop runs (reads stream
     mid-turn), but the final gate is stamped `read_only_not_applicable`
     — recorded as data, excluded from pass-rate columns (the honest-
     oracle law is intact: the task DECLARES itself read-only; laziness
     cannot manufacture a vacuous pass because mutation tasks still gate).
   - Mutation prompts route exactly as before.

2. **Fail-fast grading tier (analyzer before tests).** When the final gate
   is a test command and edits landed, a scoped `dart analyze` runs FIRST:
   an analyze failure IS the failure data (named, with the analyzer's
   output) and skips the ~20–40s test compile. Tests run only when analyze
   is clean. The oracle is never diluted — it is invoked less.

3. **Reasoning beats (ADR 0021 applied to thinking).**
   - `AcpMoveProposal` gains `reasoning` (`none|low|high`) — a
     classification hint from the daemon (read directives → none;
     structured edits → low; free-form/decomposition → high). The pi
     extension maps it to model/thinking config: routine moves go cheap;
     frontier thinking is reserved for decomposition and repair. The
     mover seam is a POLICY, not a model (tiny-model-first).
   - `AcpMoveResponse` gains `thinking` — the client's reasoning, captured
     by the daemon as a per-session record: measured (character count in
     the ledger/verdict line), NOT re-projected into future cuts
     (reasoning is one decision's business — no context rot), and REUSED
     mechanically on escalation: the extracted excerpt rides the repair
     hint so the next round starts from the previous round's constraints.
   - An empty move (no tool calls, no text) is classified
     `mover_refusal` — a bounce, named data, never a silent empty pass.

4. **Warm path is the default path.** The pi extension spawns the AOT
   binary when present (env override), `dart run` only as fallback; the
   connect-if-live socket attach (production #5) remains first choice.
   Retry/backoff becomes extension configuration (env), and gate phases
   run against independent fixtures and may proceed concurrently.

5. **Measured both ways.** Every change is measured in the scripted
   (LLM-free) path AND the real-AFM path (the North Star backend): the
   read-directive path is in-process-benched against the published
   ~68s row; AFM runs are env-gated and skip honestly when the engine is
   unavailable. Results land in `results_seam_speed.md`.

## Non-goals

- No daemon-side test caching / warm test servers: the workspace
  convention is the oracle; it is invoked less, never weakened.
- No daemon-side model routing yet: the `reasoning` hint is consumed by
  the client (pi) today; a local tiny-model mover for `none`-class
  decisions is the follow-up once measured.

## Consequences

- Read-heavy gate phases drop from minutes to the model round-trip time
  (mechanical reads) — the dominant cost item is removed, not tuned.
- Reasoning cost becomes visible (ledger column) and contained (never
  re-projected, reused only on repair).
- `mover_refusal` joins the failure-class taxonomy with its repair hint.
