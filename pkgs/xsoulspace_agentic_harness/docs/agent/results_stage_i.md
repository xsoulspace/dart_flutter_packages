# Stage I — measurement & stewardship results (I1–I4)

> Backend: on-device `AppleFoundationNativeClient` (macOS 26.6.2, arm64,
> Foundation Models), native tool calling. Decision path: one
> `act_with_project` tool (closed enum) + `intent_define` + `intent_call`
> (+ `run` for the AFM slice). Tokens source: `Situation.tokensUsed`
> (projection tokens = honest spend); AFM does not report backend usage.
> Escalations: single-tier AFM structurally produces 0 (recorded, not
> hidden). Raw logs: `benchmark/runs/intent_closure_afm_run*.log`.

## The zoom finding (I1, the big one)

The AFM bookmark build **overflowed the 4096-token context** at move ~28
(content = 12,055 tokens). Root cause was NOT the meaning tree — it was the
**feedback channel**: every move ack returned a budgeted view cut, and for a
small tree that cut was effectively the WHOLE tree (the old cut had a
fill-with-all fallback). AFM's native session accumulates every tool result,
so 28 full-tree acks ≈ 28 tree copies.

**Fix = the view cut is a ray PROJECTION with zoom levels**
(`meaningZoomLevels = [point, local, region, summary]`), not an ad-hoc flag:

- `point` — zoom IN: focus nodes + their edges (stable handles render even
  when the other endpoint isn't admitted). Move acks use this: feedback is
  **O(1) in tree size**. NO fill.
- `local` — default: focus + 1-hop + query ray-cast hits + small-tree fill.
- `region` — zoom OUT: seeds + 2-hop. No fill (keeps the zoomed-out contract).
- `summary` — zoom OUT fully: structuralize/destructurize. No node details;
  kind histogram + edges aggregated by `from --rel--> to` kind.

Architectural points (per the projection law):

- **Ray-cast hits are SEEDS**: a query hit expands its neighborhood by the
  zoom radius — relevance frontier, not just a list of nodes.
- **Per-decision strategies**: a mover ack zooms to `point` (what changed);
  `list` can zoom out on demand. Nothing prevents two actors in the same
  world from holding different strategies (mover: point; overseer: summary)
  — the zoom is a per-call knob on a shared world, which is exactly the
  multi-actor shape (one actor takes small decisions, another holds the
  bigger picture without details).
- **Zoom vocabulary is closed + countable** (stewardship probe in
  `test/structured_editor_test.dart`), same D3 law as the sub-action enum.

Effect (same task, same model, same surface):

| arm | content at context error | outcome |
|---|---|---|
| full-tree move acks | 12,055 tokens (overflow at ~28 moves) | FAIL (context) |
| point-zoom move acks | never overflowed; runs completed 8–10 decisions, 95–145 tool rounds | FAIL for *model-capability* reasons (below) — the channel no longer is |

## Meaning-executor arm vs hand-written-write (I1/I2 scripted)

Same behavior (bookmark manager), two arms, scripted (LLM-free, so the
numbers are **structure** numbers, not token numbers):

| arm | surface moves | rounds | oracle |
|---|---|---|---|
| `intent_01` (hand-written write) | 1 big `write` | 1 | intents checker (real dart) PASS |
| `intent_02` (meaning-executor: 2 intent_defines + 9 op adds + 10 links + materialize + 2 intent_calls) | 24 tiny moves | 24 (needed the round-cap lift to 48) | intents checker (real dart) PASS |

- Both materialize the SAME `program.dart` contract and pass the SAME
  intent-graded oracle. The meaning arm's op chains ARE the program; the
  interpreter and the materialized Dart are pinned by the PARITY test.
- Structural cost of the meaning arm: ~24 decisions × tiny selection tokens
  vs 1 decision × whole-file tokens. Which wins on real tokens is an AFM
  question (below), but the meaning arm additionally **exposes its logic as
  callable intents** (self-verification without stdout parsing).
- Matrix finding: the default 16-round chain cap structurally truncates
  move-dense arms; `intentClosure` tasks lift it to 48.

## AFM intent-closure runs (I3)

Driver: `pkgs/xsoulspace_inference_apple_foundation/bin/intent_closure_afm.dart`
(mirrors the suite: verifier-in-the-loop, intent-graded oracle = the SAME
`intents` checker replaying real `dart run intent_runner.dart`; max 3
mechanical retries — no LLM in the retry loop itself).

Run-by-run (all four logs kept; failures are data):

1. **run1 — context overflow** (12,055 tokens): 28+ correct-looking moves,
   oracle never ran. → produced the zoom fix above.
2. **run2 — premature completion, recovered mechanically**: model declared
   "built successfully" after 8 rounds with 3/10 ops materialized; verifier
   fed the failure back; model repaired. Final oracle error exposed a REAL
   divergence bug: materialized `program.dart` THREW
   `Null is not a subtype of String` while the in-process interpreter
   returns errors-as-data.
   → fixed: template VM is now a faithful transcription of `_MeaningVm`
   (same guards, same `$a` coercions, same error shapes); both wrapped so
   exceptions produce the same `{'error': ...}` shape. Pinned by the
   FAILURE-PATH PARITY test.
3. **run3 — actionable errors → self-repair**: op-level errors now carry the
   op id (`starts_with without prefix (op op_2)`). The model used
   `set_prop` targeted at the exact broken ops (2 repair moves). Still
   failed on dangling then-chains → added **host chain validation at
   materialize time** (`validateMeaningProgram`, problems reported in the
   materialize ack with op ids) — the heavy lifting stays host-side.
4. **run4 — append-only accretion (honest FAIL)**: 8 decisions, 122 tool
   rounds, 20 `set_prop` repairs, but retry accretion (append-only tree,
   no deletions) left `save_url` without a valid impl chain →
   `no meaning executor`. Model capability × long-horizon × accretion, NOT
   a channel problem.

**Standing-rule ledger for the I3 slice**: backend = AFM on-device; decision
path = native tool calling through one collapsed surface; tokens = projection
tokens (honest spend, 13–17k across runs); tool surface = 4 tools; escalations
= 0 (single tier); pass rate = 0/1 for the end-to-end AFM slice — with the
channel, oracle, and repair loop all validated scripted (279 → 281 tests
green) and every AFM failure classified (context / divergence / capability).

Verdict: the *harness mechanics* of intent closure are proven on-device
(model picked 100+ meaning moves, materialized real Dart, called its own
intents); the *2–4k model alone* does not yet converge the full bookmark
executor under accretion. Next lever candidates (recorded, not built):
macros arm (`1 tool + enum + macros`, fewer/bigger moves), tree compaction
between retries, or overseer-actor repair (I1 zoom strategies across actors).

## Prose host #2 (I4)

`test/prose_host_test.dart`: one sentence → `outlineFromSentence` (pure host
program) → outline as meaning nodes kind `section` (SAME tree, D1) → fills
as TextContent beats, facet-indexed, ray-projection-reachable per section →
`evidence` tier rows with `passed: null` BY CONSTRUCTION (never a loud pass,
ADR 0014 §3), same one-tool collapsed surface (D3). Proves the meaning tree +
projection + collapsed surface generalize beyond code.
