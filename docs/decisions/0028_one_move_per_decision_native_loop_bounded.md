# ADR 0028 — One move per decision: the native tool loop is not a decision loop

- Status: Accepted (2026-09-06)
- North Star impact: `clarifies` — applies the context-ownership law
  (0018) to ROUND granularity; native tool calling (0013) stays the
  default decision path, now bounded to one executed move per decision.
- Builds on: [0013](0013_native_tool_calling_first.md),
  [0018](0018_meaning_view_zoom_projection_context_ownership.md),
  [0020](0020_cut_composition_api.md),
  [0027](0027_reads_are_not_builds_reasoning_beats.md), and last_answer
  ADR 0004 (the meaning runtime; beats cross the boundary, the
  transcript is derived).
- Related: `pkgs/xsoulspace_inference_apple_foundation/bin/
  afm_context_probe.dart` (the measuring probe),
  `pkgs/xsoulspace_agentic_harness/benchmark/runs/delegation_r9.md`
  (findings 13–15), `bridge/src/bridge.swift` (session contract).

## Context

R9.1 investigation A instrumented the native side end to end and
measured (delegation_r9.md finding 13, n=1 per row):

1. **No cross-decision accumulation exists.** The FFI bridge creates a
   FRESH `LanguageModelSession` per decision — the native side is
   already stateless-per-decision. Reset at decision granularity is a
   verified fact, not work.
2. **Within a decision, the native tool loop accumulates append-only.**
   `session.respond` executes tools inline and appends every raw result
   to the transcript; the model re-reads everything on every round
   (measured: baseline 1,037 → round 1 2,562 → round 2 2,735 → final
   3,673 native tokens; ~9k token-rounds consumed against a ~2.7k flat
   estimate). Those rounds' context is never ray-cast, never ranked,
   never budgeted — the model reads raw tool output the harness never
   composed.
3. **The chars/4 estimator undercounts the native tokenizer ~45%** on
   JSON-heavy cuts (a 7,330-char "2,048-token" cut = 3,101 native), so
   constant budgets are wrong in both directions: requests are cut or
   rejected that would fit, and requests pass pre-flight that are
   natively over the TRUE 4,096 window (`model.contextSize`).
4. A JSON-dominant prompt can fail AFM's language gate ("An unsupported
   language or locale was used") — a distinct named error from
   `exceeded_context_window`.

The architectural reading: the harness's composition law — context is a
careful ray-cast of beats, picked by algorithms and planning (ADR 0018:
"context is harness-owned") — held at DECISION granularity and silently
lapsed at ROUND granularity whenever the native loop ran more than one
round. The native tool loop is a second decision loop the harness does
not govern. Flat tokens/decision (the North Star claim) is only
literally achievable when the harness composes every token the model
sees; append-only native accumulation is anti-flat by construction.

## Decision

1. **The native side stays a stateless generation primitive.** One
   decision = one fresh native session = one generation call. No
   session reuse, no cross-request transcript, no native memory. This
   is the verified bridge contract and it does not change.
2. **ONE executed tool call per decision — a CONTRACT, not a
   preference.** Backend-agnostic harness law: whatever the backend
   (Apple Foundation inline loop, OpenRouter structured calls, future
   providers), a decision executes at most one tool call. Enforcement
   is mechanical, at the two per-decision entry points where tool calls
   enter the world:
   - **Native inline path** (`WorldToolBridge`, the per-decision
     bridged registry): the first `_routeToolCall` executes; subsequent
     calls within the same decision return a NAMED contract bounce
     (`contract: one_move_per_decision`, naming the executed and
     dropped calls plus the repair hint) and are NOT executed — no
     `ToolCallEvent`, no side effects.
   - **Client-parsed path** (`DefaultGenerationHandler`, the real-model
     handler): a model response carrying multiple tool calls keeps its
     FIRST call; the rest ride [ActorGenerateResponse.droppedToolCalls]
     so the response processor records them as contract-violation result
     beats (projection-visible, never executed) — the next decision's
     cut carries the repair hint.
   **Domain boundary.** The contract binds MODEL decisions only — the
   two paths above are the only places model tool calls enter the
   world. LLM-free scripted seams (test movers building their own
   responses) and the daemon's mechanical directive relay (operator
   directives, no model in the loop — batching by design, ADR 0027)
   never accumulate model context and never populate
   [droppedToolCalls]; they are out of the contract's domain by
   construction, with no escape hatch reachable from any inference
   backend.
   The model recovers through the existing repair-hint pattern: it ends
   its turn, and the NEXT decision starts fresh — with a cut that
   re-admits the prior tool result as a projected, budgeted beat.
   Context ownership (0018) thereby holds at every token the model
   ever sees.
3. **The prior move re-enters only as projection.** The next decision's
   prompt is a fresh cut that includes the previous tool result as a
   relevance-ranked beat — never the raw accumulated transcript. Cuts
   are bounded (sublinear); transcripts accumulate (linear). This is
   what makes flat tokens/decision literal instead of approximate.
4. **Bounded native loops are NOT the default.** Compact-result
   projection inside the native loop (Option A) remains a possible
   per-task exception for read-heavy chains, but nothing ships on that
   path until a measured task pulls it. The contract is the law; the
   exception needs its own row.

## Consequences

- **Latency, honestly named:** one native round-trip per move. This
  does NOT cost more native tokens than accumulation did — the native
  loop already re-read instructions + prompt + all prior results on
  every round; the harness loop re-reads instructions + prompt + a
  bounded cut, which is ≤ the accumulated transcript for any chain
  longer than one move. The cost is harness dispatch per move —
  mechanical, no model.
- **The teaching prompt states the contract** ("one tool call per
  decision; after the result, end the turn") and stays under the
  fixed-overhead gate (`meaning_profile_overhead_test.dart`, ≤ 1,600
  estimated tokens) by rebalancing, never by raising the gate.
- **Per-request budgets become native-truth and window-relative**
  (budget = `contextSize` − native(instructions) − native(schemas) −
  one-move headroom), replacing constants — the follow-up work pulled
  by finding 13. The contract makes that budget exact: the headroom
  term is one result + one response, not k of them.
- **Honest visibility trade-off:** contract-bounced calls are not
  recorded as `BeatToolCall` moves (they never executed); the bounce
  text is the record. If violation rates become decision-relevant,
  count them explicitly — do not re-admit silent execution.
- The verification probe (`afm_context_probe.dart`) demonstrates the
  law: sequential decisions, one executed move each, per-decision
  native context printed from `model.tokenCount(for:)` /
  `model.contextSize` — the flatness measurement.
