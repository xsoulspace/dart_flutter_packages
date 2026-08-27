# ADR 0015 — Domains live above the core; composition stays a generic seam

- Status: Accepted
- Date: 2026-08-27
- North Star impact: `clarifies` — draws the hard line between the generic
  harness (loop/projection/seams) and the *domains* it hosts (coding, long-form
  prose, screenplays, conversation). Content grows in hosts; the core does not.
- Builds on: [0007](0007_extensibility_seams_and_conformance.md),
  [0014](0014_composition_surface_and_discovery.md)
- Supercedes: any reading of ADR 0014 / `composition_surface.md` that implied
  prose/dialogue *content* (archetype meanings, prose tool defaults, prose
  structure rules, prose verifiers) belongs inside the harness core.

## Context

ADR 0014 introduced the declarative composition surface and the "general agent"
direction. In the follow-up, the plan named *"content targets"* — long articles,
screenplays, books, long conversations — as a Phase for the harness. That is an
overreach, and it must be corrected while the surface is still small.

A **conversation/screenplay/book** is a *domain* — a particular product shape
with its own document model (`last_answer`: `DocumentNode`, `Block`,
`BlockType.heading|paragraph|list|message`, `ChatRole`, `AnchorSpan`,
`DocInferencePort.chat(List<ChatMessage>)`), its own latency/shared-state
needs, and its own development cycle. So is **coding**. The harness core is
*neither*. It owns only the generic machinery: loop, projection, seams, the
declarative loop/tool/eval *shapes*, and a way to be embedded.

Two forces made the boundary a live one:
- The harness **cannot own** `last_answer`'s document domain — the repos are in
  separate development cycles; forcing `last_answer` into the harness would
  couple two independent products. The harness's job is to be a *pluggable
  host/backend* the domain may use when it helps.
- The North Star gravity: *any surface that isn't a declarative seam is scope
  creep.* Framework-ized content (prose stages, per-domain tool factories)
  is exactly that creep.

## Decision

1. **The core ships only the generic seam shapes** — `FlowSpec` / `StageSpec` /
   `ToolSurface` / `renderFlow` / `DatasetSpec` / `EvalTier` / `EvalBackend`
   — all domain-agnostic. The `FlowSpec.archetype` is a **free-form label the
   host owns**; the core never interprets "prose" vs "coding" vs "dialogue".
   The removed `TaskArchetype` enum / `defaultToolSurfaceFor` were domain
   content and are gone.

2. **Coding is a domain too.** Even a "coding agent" is a host composing a
   loop + tools over the same seams; it is not the core. Tool surfaces for a
   coding flow are the host's to define.

3. **A host wraps the harness through the existing embarkably public surface**
   (`AgentWorldSetup` + `HarnessLoop` + `DecisionFlow` + `ToolRegistry` +
   `FlowSpec`). No new speculative `AgentHost`/`AgentSession` abstraction is
   added to core until three concrete hosts need it (ADR 0009 three-failures
   rule). We do not add a speculative second loop-host.

4. **Content / dialogue / screenplay mechanics live in the host** (e.g.
   `last_answer`: `DocInferencePort`, chat/screenplay document work, format
   templates, prose lint/verification). Those are product work, not engine
   work.

5. **Embedded-vs-ACP is a host-side decision, not a harness decision.** When a
   host needs **stateful, low-latency, shared-memory** work (a conversation on
   a span, drafting a screenplay as a live thread) it embeds the harness
   in-process. When it needs **general, parallel, or cross-process** work it
   uses ACP (spawned agent, streaming layer). Both are behind the host's own
   inference/document port; the harness offers in-process embedding, ACP offers
   the wire. The harness core does not pick for the host.

## Non-goals / anti-patterns

- No `TaskArchetype` enum in core. No `defaultToolSurfaceFor(archetype)`.
- No "prose structure as a harness feature" (structure-as-beats for a
  screenplay is a host concern, not an engine concern).
- No new embedded-host abstraction beyond the five seams / existing
  `HarnessLoop` surface until three hosts prove they need one.
- No forcing `last_answer`'s domain into this repo.

## Consequences

- The harness stays reviewable, provider-agnostic, and content-free; the `FlowSpec`
  becomes a true modding seam (ADR 0007).
- Hosts (coding agent, dialogue app, screenplay tool) each compose the same
  generic shapes with their own tools/verbs/tier choice.
- Embedding via `HarnessLoop` stays the flat/low-latency path; general/parallel
  work goes over ACP.