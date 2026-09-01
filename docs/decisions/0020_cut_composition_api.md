# ADR 0020 — The cut is a composed document: slots, per-slot policies, and an input gate

- Status: Accepted
- Date: 2026-09-02
- North Star impact: `clarifies` — operationalizes ADR 0018 (zoom projection,
  context ownership) into a testable composition API; no law is changed.
- Builds on: [0007](0007_extensibility_seams_and_conformance.md),
  [0009](0009_goals_as_vectors_plans_as_projections.md),
  [0013](0013_native_tool_calling_first.md),
  [0018](0018_meaning_view_zoom_projection_context_ownership.md),
  [0019](0019_code_law_absolute_long_horizon_tier.md)
- Related: `pkgs/xsoulspace_agentic_harness/test/cut_composition_test.dart`,
  `pkgs/xsoulspace_agentic_harness/benchmark/runs/delegation_m1_evidence.md`

## Context

A live native-tool delegation (N4, deepseek-v4-flash) failed with an
exploration loop: 27 decisions, 50 tool rounds, the same `list_dir`/`glob`/
`read` cycle, never writing the target file. Tracing the actual context the
model received per decision found the cause in the CUT, not the model:

1. **The cut is one flat relevance-ranked list** rendered by the messages
   codec as if it were a conversation: system prompt sandwiched mid-sequence,
   tool results out of order, empty `asst:` fragments interleaved. A frontier
   model is trained on strict alternation; a scrambled soup is
   out-of-distribution input.
2. **No deduplication**: identical tool-result beats consumed multiple beat
   slots (`maxBeats=8`).
3. **Empty text beats admitted** as empty assistant fragments.
4. **No working-set guarantee**: the 8-beat cap evicted exactly the facts the
   model needed (the goal text, the read test file), so it re-read and
   re-explored every turn. The loop was the predictable output of an amnesiac
   context — a harness failure, not a model failure.

The repair principle (deliberately NOT "render chronologically"):

**A model call is one stateless chat.** There is no conversation to preserve;
there is only this decision's view. If the view is wrong, the *ranking* is
wrong — and ranking is a per-decision-kind policy that can be declared,
adjusted, and verified, not a global sort order. "Chronology" is at most one
slot policy (for observations), never a law.

## Decision

1. **The cut is a composed document with typed slots.** A decision kind
   declares a `CutComposition`: an ordered list of `CutSlot`s, each with a
   fill source, capacity, and policies (dedup, drop-empty, required). The
   projection fills slots; the codec renders slots in declared order,
   verbatim. The codec never re-ranks or guesses.

2. **Per-slot ranking policies** replace the flat ranking:
   - `system` — static system prompt (rendered as the system role).
   - `goal` — the actor's Goal text / decision prompt. **Non-evictable.**
   - `map` — workspace graph cut (file graph, stage N5b). **Non-evictable**;
     rendered as an explicit absence when no provider is wired.
   - `observations` — tool-result and narration beats; selection by relevance,
     render order oldest→newest (recency as the slot's render policy);
     deduped; empty beats never admitted.
   - `lastVerdict` — the most recent mechanical verdict detail.
   - `plan` — plan-frontier steps (ADR 0009), unchanged semantics.

3. **Input gate.** A hard-required slot that cannot fill (no goal on a
   granted actor) is a named `CutCompositionException` BEFORE the model is
   called — the input-side mirror of the write gate. Soft-required slots
   (map, lastVerdict) render as explicit absences when their source does not
   exist yet. Every emitted cut conforms to its composition or nothing is
   sent.

4. **Conformance suite (LLM-free).** Per composition: slot order, no
   duplicates, no empty fragments, required slots filled, working set
   survives eviction pressure. A composition that cannot state its invariant
   does not ship; published rows stamp their composition.

5. **model ≠ actor.** A role = (composition + tool surface + model binding).
   Many actors may share one model; one local model may field an entire squad
   offline (AFM coder + writer + overseer). Roles are data over the same five
   seams (ADR 0015); the overseer's summary-zoom brief is the first role-
   specific composition.

## Consequences

- The flat ranked cut remains the default for existing flows until a host
  declares a composition (no breaking change); `runCodingAgentOnce` and the
  daemon declare the coder composition.
- Flatness gates continue to assert tokens/decision boundedness WITH the
  working-set guarantee — flatness must not be bought with amnesia.
- The fs file graph (N5b) is the data source for the `map` slot; exploration
  loops become structurally impossible rather than prompt-patched.
- Token accounting includes the working set (honest spend).

## Non-goals

- No chronological-rendering law for the whole cut (rejected: conversation
  semantics through the back door).
- No embedding retrieval in this change (relevance stays keyword-
  deterministic; the seam exists in `relevance.dart`).
- No per-turn dynamic re-composition by the model (the model never tunes its
  own context; compositions are host data).

## Validation

- `cut_composition_test.dart`: slot order, dedup, drop-empty, required-slot
  input gate, working-set survival under eviction pressure — all LLM-free.
- Live re-delegation of the N4 failure task; the exploration loop is gone
  and the check passes.
