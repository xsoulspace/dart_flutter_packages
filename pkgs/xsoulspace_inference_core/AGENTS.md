# pkgs/xsoulspace_inference_core: Agent Working Agreement

Provider-agnostic inference contracts and validation utilities for text, STT,
and TTS task flows. This package is part of the `dart_flutter_packages`
workspace; Skill Steward is adopted at the workspace root with package-scoped
actions.

## Purpose

Inference backends are unreliable by nature (timeouts, malformed JSON, partial
responses). This package centralizes task contracts, validation, and failure
shapes so all providers expose consistent behavior.

## Agentic Harness

This package also hosts a **UI-agnostic, cinematic multi-actor agent harness**
built on ecsly. The harness is the intelligence amplifier; the model is a
replaceable reasoning primitive. It is a living, multi-linear, game-like world
where actors (LLM, human, or other) act, think, plan, research, use tools, and
make decisions. Everything is an entity. The graph is formed by typed reference components. Stories interlink. The LLM is reduced to exactly one role: *produce the next beat*. **Every part of the engine except "write a beat" is deterministic graph logic**.

### Core thesis

- **Projection** produces an extremely limited *Situation* (a "film cut") per
  actor — only props in frame, co-present actors, the local question, explicit
  absences. Context windows stay tiny.
- **Agency** is granted only when a genuine `OpenDecision` exists. Everything
  else is mechanical (no LLM calls).
- **Threads** are first-class exploration branches; **Beats** are
  modality-agnostic content units (text, voice, tool calls, thoughts,
  observations).
- **Everything is an entity.** The graph is formed by typed reference
  components. Stories interlink; multiplayer is natural.
- **The loop is continuous and idle-aware.** It sleeps when there is no work.

### The loop (concurrent, non-blocking)

```
Tick N:   Ingest -> Narrative -> AgencyGrant -> Project -> ActorAct (dispatch LLM calls, fire-and-forget) -> flush
Tick N+1: Ingest -> Narrative -> AgencyGrant -> Project -> ActorAct (dispatch new calls) -> ProcessResponses (process whatever arrived) -> Mechanical -> flush
```

`ActorAct` dispatches LLM calls concurrently and returns immediately;
`ProcessResponses` processes whatever responses arrived on that tick. The loop
never blocks on a single LLM call. Idle/sleep only when no work remains.

### Where it lives

- `lib/src/agent` folder. — `Model`, `ModelRouter`, `ModelRuntime`, `AgentId`
- `lib/src/agent/agent_plugin.dart` — `AgentPlugin` (components, resources,
  event channels, schedules), agency/projection/act/response/tool systems
- `lib/src/agent/agency_lifecycle.dart` — `AgencyLifecycle` (grant/consume/retry rules)
- `lib/src/agent/harness_loop.dart` — `HarnessLoop` (headless/CLI schedule driver)
- `lib/src/agent/narrative.dart` — Thread & Beat ontology, graph-forming systems
- `lib/src/agent/tool_call_parser.dart` — `ToolRegistry`, `ToolDef`, tag parser
- `lib/src/agent/structured_output/` — `SchemaBundle` + `GenerationSchemaHandle`
- `lib/src/agent/PLAN.md` — implementation plan (vision, loop, ontology)
- `lib/src/agent/discussion.md` — design rationale and open tensions

### Schedules (installed by `AgentPlugin`)

1. `AgencyGrant` — grant `Agency` to actors with `OpenDecision`
2. `Project` — build minimal `Situation` for actors with `Agency`
3. `ActorAct` — dispatch generation requests (async-parallel, fire-and-forget)
4. `ProcessResponses` — handle LLM responses, dispatch tool calls
5. `Mechanical` — execute tools, score/prune/merge threads
6. `Narrative` — advance Thread/Beat playheads, finalize partials

### Concurrency & integration

- LLM I/O flows through registered event channels
  (`ActorGenerateRequest` / `ActorGenerateResponse` / `ActorGenerateStreamEvent`,
  `ToolCallEvent` / `ToolResultEvent`) and `TaskRegistryResource` tracks in-flight
  tasks.
- For Flutter apps, prefer `EcsFixedStepLoop` from `ecsly_flutter` (drives the
  same schedules on the Flutter frame ticker). `HarnessLoop` is for headless/CLI
  use or full loop control.
- **Do not call LLMs directly in systems.** Route generation through
  `GenerationHandlerResource`; the loop stays non-blocking and retry-safe.

### Design invariants

- Agency is granted by systems, never assumed by actors.
- Projection is ruthlessly minimal — tiny context windows are the goal.
- Tool calls are first-class Beats with a strict tag protocol
  (`<getDefinition|tool>` / `<call|tool|{...}>` / `<result|tool|{...}>`).
- Threads are scoreable, prunable, and mergeable; pruned threads stay queryable
  for history.

## Where Things Live

- Public API: `lib/xsoulspace_inference_core.dart`
- Implementation: `lib/src/`
- Tests: `test/`

## Validation

Native package loop (requires Flutter SDK for workspace resolution):

```bash
cd pkgs/xsoulspace_inference_core
flutter pub get
flutter analyze
flutter test
```

Steward-scoped actions (from repo root):

```bash
steward action xsoulspace_inference_core.analyze
steward action xsoulspace_inference_core.test
```

## Docs To Update

If you change public usage patterns, update `README.md` and `CHANGELOG.md`.
