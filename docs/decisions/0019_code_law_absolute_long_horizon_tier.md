# ADR 0019 — The law is absolute for code (verifiability, not model size); the long-horizon tier is the headline measurement; growth is intent-first

- Status: Accepted
- Date: 2026-09-02
- North Star impact: `clarifies` — hardens the coding law (scopes it by
  verifiability, explicitly NOT by model size), realigns the benchmark
  program to the axis where the harness claim actually binds, and promotes
  the self-extending vocabulary from frontier to load-bearing.
- Builds on: [0007](0007_extensibility_seams_and_conformance.md),
  [0009](0009_goals_as_vectors_plans_as_projections.md),
  [0013](0013_native_tool_calling_first.md),
  [0015](0015_domains_live_in_hosts_core_stays_generic.md),
  [0018](0018_meaning_view_zoom_projection_context_ownership.md)
- Related: `pkgs/xsoulspace_agentic_harness/docs/agent/plan_long_horizon_tier.md`,
  `pkgs/xsoulspace_agentic_harness/docs/agent/plan_fair_pi_comparison.md`

## Context

Two discussion findings, both grounded in existing measured data:

1. **The harness provides two services with different transfer profiles
   across model size — and only one of them touches the grammar.**
   Context/world management (decomposition, projection, budgets,
   persistence, multi-actor shared state) is *relative*: no context window
   (1M included) solves attention degradation over long logs, cross-task
   persistence, or state shared by several actors; it transfers unchanged
   from a 4k model to a frontier model, and a smarter model makes every
   harness-level decision better. A proposal to relax the coding law for
   large models ("direct profile": native fs edits for mainstream stacks)
   was considered and **rejected** — see Decision §1.

2. **The benchmark program never measures the axis where the North Star
   claim binds.** The 20-task suite tests short, single-session,
   mainstream-stack coding — the home turf of conversation-log agents with
   direct-edit grammars. The harness's structural wins (flat tokens/decision
   across hundreds of beats, persistence across sessions, multi-actor shared
   world state) have no hosted-model, head-to-head measurement at all. A
   claim/benchmark misalignment, not model size, produced the discouraging
   6/20-style numbers.

3. **ACP status correction.** The ACP *server* already exists
   (`dart_acp_toolkit` in the IntentCall workspace: stdio JSON-RPC,
   capability negotiation, pluggable `AcpAgentBackend`; client already used
   by `xsoulspace_inference_acp`). The remaining gap is one adapter: a
   harness-backed `AcpAgentBackend` (over `coding_agent.dart --json`) and a
   recorded live Zed session.

## Decision

1. **The law is absolute for code, regardless of model size.**
   "The model never writes code tokens, never sees an AST, never holds the
   whole tree" holds for a 4k on-device model and for a frontier hosted
   model alike. Grounding — the law tracks **verifiability, not artifact
   type or model size**:
   - Code has closed semantics (interpreter / materialized-program /
     graded oracle): correctness is decidable, repair localizes to op ids,
     and composition is verifiable. The model composes meaning; the host
     materializes. All code generation goes through the meaning pipeline.
   - **Untrained and invented languages are the strongest case FOR the
     law, not against it**: a frontier model asked to write code in a
     language absent from its training data hallucinates confidently; asked
     to invent a language it fails structurally. The harness path is the
     only reliable one — the model proposes the vocabulary itself *as data*
     (op-specs / materializer spec), the host verifies it, and composing
     programs in the new language becomes a closed-semantics problem the
     harness already solves. "Invent a language" and "grow the vocabulary"
     are the same operation, and neither requires model code-tokens.
   - Accepted cost, on the record: on short, mainstream-stack coding tasks
     a direct-editing conversation agent will likely beat the meaning
     profile, and we publish that loss honestly (conventional tier). The
     bet rests on the long-horizon tier, untrained/invented languages,
     on-device economics, and multi-actor persistence.

2. **Free-form text was never under the law.** Documentation, prose,
   dialogue, long-document work (e.g. last_answer) are open-semantics
   artifacts: there is no falsifiable oracle, which is exactly why they
   route to the `evidence` tier (North Star guardrail) and never `pass`.
   The model writes text freely, small or large; where a text artifact has
   checkable properties (structure, links, schema, budgets), mechanical
   verifiers apply to those properties. Text domains are host domains over
   the same five seams (ADR 0014/0015) — not a grammar exception.

3. **The long-horizon tier is the headline measurement** (Phase 8): hosted
   model (OpenRouter, native tools per ADR 0013) on both harnesses (ours vs
   pi SDK), multi-session, cross-task, repo-scale workloads with hundreds of
   beats and mid-run snapshot/restore. Hypothesis: the conversation-log
   agent degrades (linear log + attention degradation); the harness stays
   flat. Protocol and columns:
   [plan_long_horizon_tier.md](../../pkgs/xsoulspace_agentic_harness/docs/agent/plan_long_horizon_tier.md).
   The existing 20-task suite is re-labeled the **conventional tier** — a
   fair loss there is expected and honest (Decision §1).

4. **Intent-first growth is load-bearing, not frontier.** The growth
   mechanism already exists in three layers:
   - **Ops** are the substrate — the closed op vocabulary of the meaning
     tree (`load_arg`, `jump_if_false`, `return`, …).
   - **Intents are the self-extending primitive — already landed**:
     `intent_define` is ONE self-executing action that requires specs and
     always wires the `impl` edge; `intent_call` is both the calling
     convention and the in-process oracle; intent closure v1 pins
     interpreter ⇄ materialized-Dart parity; macros compose whole chains
     (5 moves vs 24 micro-moves). A model (or human) proposes a new intent
     AS DATA; the host verifies it mechanically; it becomes callable
     everywhere. Growth = defining intents, not hand-editing op sets.
   - **Surfaces**: AE (`~/xs/agentic_executables`; ADR 0017/D2) owns
     durable truth + tiered verification of specs — one canonical, many
     realizations, drift surfaces as tier-classified gaps. IntentCall
     (`~/mcp/cline/intentcall`) projects registry intents to MCP, WebMCP,
     ACP (`RegistryAcpBackend`), and platform surfaces — the same intent an
     actor defines in-world is callable by other actors (a2a) and by
     editors/assistants. The harness core stays generic (ADR 0015); these
     are sibling projections of the same intent truth.
   With the direct profile rejected, intent-first growth is the ONLY path
   for the meaning profile's expressiveness ceiling — and it doubles as the
   invented-languages mechanism (Decision §1): an invented language = an
   intent set + a materializer spec, both data, both host-verified.
   Priority raise: model-proposed intent growth is sequenced as the
   successor to the current J/K stages, ahead of any hand expansion.

5. **General agent first; coding is the first application.** Free-form
   generation surfaces are host domains over the same seams with their own
   tool surfaces and verifiers (ADR 0014/0015); eval-tier honesty is
   unchanged (Decision §2).

6. **Cost columns are adoption metrics, not claim metrics.** `cache_hit_rate`
   and $/task are recorded beside the long-horizon results (deterministic
   projection makes prefix stability reachable) but never substitute for the
   tokens/decision flatness and persistence claims.

## Consequences

- `pipeline_coding.md`'s law statement is restated with its verifiability
  grounding and its explicit size-independence; the run-graded arm's
  teaching-prompt contradiction ("make the change with write", P4) is a
  named violation of the now-absolute law and closes ONLY via P4 span
  edits — there is no profile escape hatch.
- The fair-pi comparison keeps its plan but is subsumed as the conventional
  tier of the Phase 8 program; its tool-parity and model-pinning rules carry
  over.
- New work item: `HarnessAcpBackend` + live Zed proof (small; the transport
  exists).
- New work item: multi-session flatness gate in CI (scripted, LLM-free) —
  `test/long_horizon_multi_session_test.dart` pins tokens/decision flatness
  across snapshot/restore session boundaries.
- Priority raise: intent-first growth (Decision §4) sequenced as the
  successor to the current J/K stages, ahead of any vocabulary-by-hand
  expansion.

## Non-goals

- No direct-edit grammar for code at any model size (rejected; see Decision
  §1 and the accepted conventional-tier cost).
- No conversation-mode adoption for persistence ("memory as context" stays a
  bug class per ADR 0018/D7).
- No claim, yet, that the harness beats a direct-grammar agent on the
  conventional tier — the honest ledger keeps that open, and expects to
  lose it.

## Validation

- Scripted multi-session flatness gate in CI (`long_horizon_multi_session_test.dart`).
- Phase 8 matrix run per the long-horizon tier plan; every row stamped with
  domain, backend, decision path, tokens source, n.
