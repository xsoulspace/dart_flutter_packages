# Agent Harness Implementation Plan

> **Status**: Active
> **Goal**: Build a general-purpose, UI-agnostic, cinematic multi-actor agent harness on ecsly.
> **Core thesis**: The harness is the intelligence amplifier. The model is a replaceable reasoning primitive.

---

## 0. Vision Summary

A living, multi-linear, game-like world where:

- **Actors** (LLM, human, or other) act, think, plan, research, use tools, and make decisions.
- **Projection** produces an extremely limited *Situation* (a "film cut") for each actor — only props in frame, only co-present actors, only the local question, explicit absences.
- **Agency** is granted only when a genuine `OpenDecision` exists. Everything else is mechanical (no LLM calls).
- **Threads** are first-class exploration branches. **Beats** are modality-agnostic content units (text, voice, tool calls, thoughts, observations).
- **Everything is an entity.** The graph is formed by typed reference components. Stories interlink. Multiplayer is natural.
- **The loop is continuous and idle-aware.** It sleeps when there is no work.

### The Loop (Concurrent, Non-Blocking)

```
Tick N:   Ingest -> Narrative -> AgencyGrant -> Project -> ActorAct (dispatch LLM calls, fire-and-forget) -> flush
Tick N+1: Ingest -> Narrative -> AgencyGrant -> Project -> ActorAct (dispatch new calls) -> ProcessResponses (process whatever arrived) -> Mechanical -> flush
Tick N+2: ... (same pattern, responses from Tick N may arrive here)
```

Key: `ActorAct` dispatches LLM calls concurrently and returns immediately. `ProcessResponses` processes whatever responses have arrived on this tick. The loop never blocks on a single LLM call. Multiple actors' LLM calls run concurrently. Idle/sleep only when no work remains.

---

## 1. Current State

### 1.1 What Works

| Component | File | Status |
|---|---|---|
| `Actor`, `ActorModel`, `ActorSystemPrompt`, `ActorTools` | `agent_plugin.dart` L19-46 | Registered, tested |
| `ActorRuntimeMemories`, `ContextFragment` | `agent_plugin.dart` L52-64 | Registered, tested |
| `Agency`, `OpenDecision` | `agent_plugin.dart` L70-83 | Registered, tested |
| `Scene`, `SceneFrame`, `PresentInScene`, `PresentProp`, `Prop` | `agent_plugin.dart` L86-114 | Registered, tested |
| `Situation` | `agent_plugin.dart` L120-131 | Registered, tested (but misplaced — see 2.3) |
| `Thread`, `ThreadScore` | `agent_plugin.dart` L136-145 | Registered, tested (but minimal) |
| `Goal` | `agent_plugin.dart` L148-151 | Registered, tested (but minimal) |
| `ModelRouterResource`, `ToolRegistryResource` | `agent_plugin.dart` L161-177 | Registered, tested |
| `ActorGenerateRequest`, `ActorGenerateResponse`, `ToolCall` | `agent_plugin.dart` L187-236 | Registered, tested |
| `AgentPlugin` (5 schedules) | `agent_plugin.dart` L246-302 | Installed, tested |
| `grantAgencySystem` | `agent_plugin.dart` L313-322 | Tested |
| `projectSituationSystem` + `_buildSituation` | `agent_plugin.dart` L328-384 | Tested |
| `actorActSystem` | `agent_plugin.dart` L394-435 | Tested |
| `processResponsesSystem` | `agent_plugin.dart` L442-507 | Tested (but racy — see 2.1) |
| `scoreThreadsSystem` | `agent_plugin.dart` L512-518 | Placeholder (hardcodes 0.5) |
| `pruneThreadsSystem` | `agent_plugin.dart` L523-531 | Placeholder (threshold 0.1) |
| `ActorGenerateHandler` / `DefaultActorGenerateHandler` | `agent_plugin.dart` L542-632 | Tested |
| `EcsFixedLoop` | `ecsly_app/lib/src/ecs_loop.dart` | Draft — naive async, needs fix |
| Tests | `test/agent_harness_test.dart` | 700+ lines, full e2e |
| Apple Foundation example | `apple_foundation/example/lib/main.dart` | Manual schedule-chaining, sleep hack |
| Core example | `core/example/lib/main.dart` | Uses old `AIWorld` API, not ECS |

### 1.2 What Is Broken / Missing

| # | Issue | Severity | Location |
|---|---|---|---|
| 1 | `processResponsesSystem` executes tools with `unawaited` — racy | P0 | `agent_plugin.dart` L495 |
| 2 | `actorActSystem` removes `Agency` before LLM call completes — no retry on failure | P0 | `agent_plugin.dart` L428 |
| 3 | `Situation` is a mutable component on the actor entity — pollutes archetype | P0 | `agent_plugin.dart` L339 |
| 4 | `scoreThreadsSystem` hardcodes 0.5 — no real scoring | P1 | `agent_plugin.dart` L516 |
| 5 | `pruneThreadsSystem` threshold is arbitrary 0.1 | P1 | `agent_plugin.dart` L527 |
| 6 | No Thread/Beat ontology — `discussion.md` describes rich graph, code has none | P1 | Missing entirely |
| 7 | No `HarnessLoop` — examples manually chain schedules | P0 | Both examples |
| 8 | No idle/sleep — `EcsFixedLoop` busy-polls forever | P1 | `ecs_loop.dart` |
| 9 | `EcsFixedLoop` uses `unawaited(runScheduleAsync)` — wrong async path | P0 | `ecs_loop.dart` |
| 10 | `agent.dart` duplicates ECS concepts (`Agent`, `AgentId`, `ModelRouter`) | P2 | `agent.dart` |
| 11 | `ToolCall` name collision — event payload vs. component | P2 | `agent_plugin.dart` L232 vs. discussion.md L802 |
| 12 | No multi-actor coordination (`AddressedTo`, `PrivateToActor`, `DerivedFrom`) | P2 | Missing |
| 13 | Tool call parsing is hardcoded to tag-based parsing — should be backend-specific | P0 | `agent_plugin.dart` L621-631, `tool_call_parser.dart` |
| 14 | `ContextFragment` value is a raw string — loses structure | P1 | `agent_plugin.dart` L60-64 |
| 15 | `EventChannel` has no subscription mechanism — `forEach` is snapshot-only | P0 | ecsly `event_channel.dart` |

---

## 2. Architecture Decisions (MoE Synthesis)

### 2.1 The async execution model — ecsly's sync executor already does fire-and-forget

**Key finding from ecsly core code**: The sync executor's `_executeGroup` method (L89-91) calls `asyncParallel` systems **without awaiting**:

```dart
// system_executor.dart:78-93
void _executeGroup(World world, List<int> group, List<SystemDescriptor> systems) {
  for (final index in group) {
    final desc = systems[index];
    if (desc.mode case .sync) {
      desc.system(world);       // sync — called directly
    }
    if (desc.mode case .asyncParallel) {
      desc.system(world);       // asyncParallel — Future is DISCARDED
    }
  }
}
```

The `System` typedef is `void Function(World world)`. When `actorActSystem` (which is `Future<void> Function(World)`) is cast to `System` and called, the returned `Future` is discarded. This is **already fire-and-forget**.

**The problem**: `EcsFixedLoop` uses `unawaited(world.runScheduleAsync(name))` which goes through the **async executor** (`_executeGroupAsync`) that **does** await via `Future.wait`. This is the wrong path.

**Fix**: Use `world.runSchedule(name)` (sync path) for `ActorAct`. The `asyncParallel` mode in the sync executor already discards the Future. The `await Future.delayed(Duration.zero)` inside `actorActSystem` yields to the event loop, allowing the external handler to process events.

**Action**: Change `EcsFixedLoop._runFixedStep` to use `runSchedule` for all schedules, regardless of `isAsync` flag. The `isAsync` flag becomes a no-op (or is removed).

### 2.2 The event channel subscription gap

**Key finding**: `EventChannel` has no subscription mechanism. `EventReader.forEach()` snapshots at call time — it only iterates events that existed when `forEach` was called. Events sent *after* `forEach` returns are invisible.

The `ActorGenerateHandler.register()` method uses `forEach`, which means it only processes events that were in the channel *before* registration. This is a **fundamental bug** — the handler can never see events sent after it registers.

**Fix**: Add a subscription mechanism to `EventChannel`:
```dart
// In EventChannel<T>:
Stream<T> get stream => _streamController.stream;
void listen(void Function(T event) onEvent) => _streamController.stream.listen(onEvent);
```

Or: use a polling pattern where the host application calls `handler.processPending(world)` on each tick.

**Decision for MVP**: Use the polling pattern. The `HarnessLoop` calls `handler.processPending(world)` on each tick, which drains the request channel and sends responses. This avoids modifying ecsly's `EventChannel`.

**Action for Phase 2**: Add `Stream<T>` subscription to `EventChannel` in ecsly.

### 2.3 Backend-agnostic tool call / structured output

**Decision**: The ECS layer must NOT assume how tool calls or structured output are produced. Different inference backends work differently:

| Backend | Tool calls | Structured output |
|---|---|---|
| Apple Foundation (native) | Native bridge — no parsing needed | Native JSON schema |
| OpenAI / OpenRouter / DeepSeek | Native tool call API | Native JSON schema |
| Raw LLM (no tool API) | Parse from text (tag-based or XML) | Parse from text |
| Laguna / custom | Custom format | Custom format |

**Implementation**:
- `ActorGenerateRequest` carries the `ToolRegistry` and `SchemaBundle` as-is.
- `ActorGenerateResponse` carries `structuralOutput` (parsed `Map<String, dynamic>`) and `rawOutput` (raw string).
- **Tool call parsing is the handler's responsibility**, not the ECS system's.
- The `processResponsesSystem` receives already-parsed `ToolCall` objects in `ActorGenerateResponse.toolCalls`.

**Action**: Move `_parseToolCalls` from `agent_plugin.dart` into the handler/runtime layer. The ECS system just consumes `response.toolCalls`.

### 2.4 Prefer native ecsly API

**Decision**: Use ecsly's native APIs (schedules, resources, events, queries) wherever possible. Only add custom patterns when ecsly genuinely lacks a feature.

- Schedules for the loop phases
- Resources for global state
- Events for async LLM I/O
- Queries for entity lookups

**Action**: Audit all custom patterns against ecsly's native API before implementing.

### 2.5 `ContextFragment` -> typed Beats

**Decision**: Replace the opaque `ContextFragment` (string value) with typed `Beat` entities. This aligns with the `discussion.md` ontology and enables proper modality handling.

**Action**: Phase 1 (see 4).

---

## 3. Phase 0: Stabilize the Existing Loop (P0)

### 3.1 Fix `processResponsesSystem` tool execution race

**Problem**: Tools are executed with `unawaited(toolDef.execute(...).then(...))`. The `ProcessResponses` schedule completes immediately, but tool results land asynchronously.

**Fix**:
- Add a `PendingToolExecutionsResource` to track in-flight tool calls:
```dart
class PendingToolExecutionsResource extends Resource {
  final Set<Entity> pending = {};
}
```
- `processResponsesSystem` adds to the pending set when it fires a tool.
- A new `ToolCompletionSystem` (in the Mechanical schedule) checks if all pending tools are done.
- The `HarnessLoop` does not advance to `AgencyGrant` until `pendingTools.isEmpty`.

**Alternative (MVP)**: Make tool execution synchronous within `ProcessResponses` by awaiting all tool futures. Tools are typically fast. Only the LLM call is truly async.

**Decision**: Synchronous for MVP. Add `PendingToolExecutionsResource` for the continuous loop.

### 3.2 Fix `Agency` lifecycle

**Problem**: `actorActSystem` removes `Agency` immediately after sending the request (L428). If the LLM call fails, the actor has no Agency and no way to retry.

**Fix**:
- `actorActSystem` sends the request and adds an `AwaitingResponse` component.
- `processResponsesSystem` consumes `Agency` + `AwaitingResponse` after storing the response.
- On failure (null response): create a new `OpenDecision` with an error note, or re-grant `Agency` with a tighter Situation.

**New component**:
```dart
/// Tag: actor has dispatched an LLM request and is waiting for response.
class AwaitingResponse implements Component {
  const AwaitingResponse();
}
```

### 3.3 Move `Situation` to a resource

**Problem**: `projectSituationSystem` inserts `Situation` onto the actor entity (L339). This changes the actor's archetype every tick.

**Fix**: Store `Situation` in a per-actor resource:
```dart
class ProjectionResource extends Resource {
  final Map<AgentId, Situation> situations = {};
}
```

### 3.4 Fix `EcsFixedLoop` async handling

**Problem**: `EcsFixedLoop._runFixedStep` uses `unawaited(world.runScheduleAsync(name))` for async schedules. This goes through ecsly's async executor which awaits via `Future.wait` — wrong for fire-and-forget.

**Fix**: Use `world.runSchedule(name)` (sync path) for all schedules. The `asyncParallel` mode in the sync executor already discards the Future (see 2.1).

```dart
// ecs_loop.dart — change from:
if (isAsync) {
  unawaited(world.runScheduleAsync(name));
} else {
  world.runSchedule(name);
}
// to:
world.runSchedule(name);  // asyncParallel systems are fire-and-forget in sync executor
```

**Action**: Fix `EcsFixedLoop` in `ecsly_app`.

### 3.5 Create `HarnessLoop` (non-blocking, concurrent)

**Problem**: Both examples manually chain schedules. No async completion tracking. No idle/sleep.

**Approach**: `HarnessLoop` wraps `EcsFixedLoop` and adds:
- Pending agency counter (tracks in-flight LLM calls via `AwaitingResponse`)
- Pending tool counter (tracks in-flight tool executions)
- Idle detection (sleep when no work)

**Concurrency model**: `ActorAct` dispatches all LLM calls concurrently (fire-and-forget via sync executor's `asyncParallel` mode). The loop continues ticking. `ProcessResponses` processes whatever responses arrived on each tick. The loop NEVER blocks on a single LLM call. This enables true multiplayer: hundreds of actors' LLM calls run concurrently, and the loop processes responses as they arrive.

```dart
class HarnessLoop {
  final World world;
  final ActorGenerateHandler handler;
  bool _running = false;

  HarnessLoop({required this.world, required this.handler});

  Future<void> start() async {
    handler.register(world);
    _running = true;
    while (_running) {
      _tick();  // Non-blocking tick
      if (canSleep()) {
        await _sleepUntilWakeup();
      }
    }
  }

  void _tick() {
    // 1. Ingest (external events -> OpenDecisions)
    world.runSchedule('Ingest');
    world.flush();

    // 2. AgencyGrant
    world.runSchedule('AgencyGrant');
    world.flush();

    // 3. Project
    world.runSchedule('Project');
    world.flush();

    // 4. ActorAct (dispatch LLM calls concurrently, fire-and-forget)
    //    Uses runSchedule (sync path) — asyncParallel systems discard the Future
    world.runSchedule('ActorAct');
    world.flush();

    // 5. ProcessResponses (process whatever responses arrived since last tick)
    world.runSchedule('ProcessResponses');
    world.flush();

    // 6. Mechanical (tools, scoring, prune, notify)
    world.runSchedule('Mechanical');
    world.flush();
  }

  bool canSleep() {
    final hasOpenDecisions = world.query2<Actor, OpenDecision>().toList().isNotEmpty;
    final hasAgency = world.query2<Actor, Agency>().toList().isNotEmpty;
    final hasAwaiting = world.query2<Actor, AwaitingResponse>().toList().isNotEmpty;
    return !hasOpenDecisions && !hasAgency && !hasAwaiting;
  }
}
```

### 3.6 Fix apple foundation example

- Replace manual schedule-chaining with `HarnessLoop`.
- Register `DefaultActorGenerateHandler` via `HarnessLoop`.
- Remove `Future.delayed(2s)` hack.

### 3.7 Move tool call parsing to handler layer

- Remove `_parseToolCalls` from `agent_plugin.dart`.
- The `DefaultActorGenerateHandler` already gets `response.rawOutput` from `ModelRuntime.generate()`. The `ModelRuntime` should parse tool calls based on the backend.
- For Apple Foundation (native), `ModelRuntime` returns already-parsed `ToolCall` objects.
- For raw LLM backends, a `ToolCallParser` strategy parses the text.

**Action**: Add `ToolCallParser` interface to `agent.dart` or `tool_call_parser.dart`. `ModelRuntime` uses it.

### 3.8 Add tests for Phase 0 fixes

- Test `AwaitingResponse` lifecycle
- Test `PendingToolExecutionsResource`
- Test `HarnessLoop` continuous loop
- Test idle/sleep

---

## 4. Phase 1: Implement the discussion.md Ontology (P1)

### 4.1 Thread & Beat entities

**New file**: `lib/src/agent/narrative.dart`

```dart
// -- Thread container --
class ThreadId extends Component { final String value; }
class ThreadStatus extends Component { ThreadStatusEnum value; }
class ParentScene extends Component { Entity scene; }
class OriginActor extends Component { Entity actor; }
class GoalLink extends Component { Entity? goal; }
class DerivedFromThread extends Component { Entity thread; }
class ThreadVisibility extends Component { Set<AgentId> visibleTo; }

// -- Beat (content unit) --
class BeatId extends Component { final String value; }
class BelongsToThread extends Component { Entity thread; }
class BeatSequence extends Component { int value; }
class Speaker extends Component { Entity actor; }
class AddressedTo extends Component { Entity? actor; }
class BeatModality extends Component { ModalityEnum value; }
class BeatStatus extends Component { BeatStatusEnum value; }
class ReplyToBeat extends Component { Entity beat; }
class ObservesProp extends Component { Entity prop; }
class PrivateToActor extends Component { Entity actor; }

// -- Sparse modality payloads --
class TextContent extends Component { String text; }
class TextStream extends Component { List<String> chunks; int cursor; }
class AudioStream extends Component { /* realtime chunks */ }
class ActionPayload extends Component { Map<String, dynamic> data; }
class BeatToolCall extends Component { String name; Map<String, dynamic> args; }
class ToolResult extends Component { dynamic result; }
class ThoughtContent extends Component { String text; }
class ObservationData extends Component { dynamic data; }
```

**Note**: `ToolCall` already exists as an event payload class in `agent_plugin.dart` L232. The Beat component version is renamed to `BeatToolCall`.

### 4.2 Graph-forming systems

```dart
Entity spawnThread(World w, Entity originActor, Entity parentScene, {Entity? goal})
Entity startBeat(World w, Entity thread, Entity speaker, ModalityEnum modality)
void appendToBeat(World w, Entity beat, String chunk)
void completeBeat(World w, Entity beat)
void scoreThreadsSystem(World w)  // real scoring
void pruneThreadsSystem(World w)  // mark Pruned, don't despawn
void mergeThreadsSystem(World w)  // re-parent Beats
```

### 4.3 Register in `AgentPlugin.install()`

Add all new components. Add new schedules:
- `Narrative` — mechanical advancement, playhead movement
- `ThreadScoring` — real scoring
- `ThreadPruning` — real pruning

### 4.4 Add tests for Thread/Beat systems

---

## 5. Phase 2: Continuous Loop & Idle (P1)

### 5.1 `HarnessLoop` async completion tracking

The `HarnessLoop` uses `runSchedule` (sync path) for all schedules. `asyncParallel` systems in the sync executor are already fire-and-forget. The loop processes responses on each tick.

### 5.2 Idle/sleep

```dart
bool canSleep(World world) {
  final hasOpenDecisions = world.query2<Actor, OpenDecision>().toList().isNotEmpty;
  final hasAgency = world.query2<Actor, Agency>().toList().isNotEmpty;
  final hasAwaiting = world.query2<Actor, AwaitingResponse>().toList().isNotEmpty;
  return !hasOpenDecisions && !hasAgency && !hasAwaiting;
}
```

### 5.3 Add `Stream` subscription to `EventChannel` (ecsly)

**Phase 2 goal**: Add a `Stream<T> stream` getter to `EventChannel` so handlers can subscribe to new events without polling. This replaces the broken `forEach` snapshot pattern.

### 5.4 Multi-world (future)

The discussion.md describes a rich world (full history) and a projection world (lean context). Defer to Phase 2.

---

## 6. Phase 3: Polish Target Apps (P2)

### 6.1 `xsoulspace_inference_apple_foundation/example/lib/main.dart`

- Use `HarnessLoop` instead of manual schedule-chaining.
- Remove `Future.delayed(2s)` hack.

### 6.2 `xsoulspace_inference_core/example/lib/main.dart`

- Migrate from old `AIWorld` API to ECS `HarnessLoop`.
- Keep the 3 scenarios but reimplement on ECS.

### 6.3 Deprecate `agent.dart` old API

- Mark `AIRuntime`, `AIWorld`, `Agent` as `@Deprecated`.
- Keep shared types (`ModelRouter`, `ModelRuntime`, `Model`, `ModelId`, `AgentId`).

---

## 7. Priority Order

| Priority | Task | Why | Est. |
|---|---|---|---|
| P0 | Fix `processResponsesSystem` tool race | Current code is racy; tests pass by coincidence | 2h |
| P0 | Fix `Agency` lifecycle (add `AwaitingResponse`) | No retry on failure; broken semantics | 2h |
| P0 | Move tool call parsing to handler layer | Backend-agnostic; Apple Foundation doesn't need parsing | 2h |
| P0 | Fix `EcsFixedLoop` async handling (use `runSchedule` not `runScheduleAsync`) | Wrong async path; sync executor already does fire-and-forget | 2h |
| P0 | Create `HarnessLoop` (non-blocking, concurrent) | Examples need continuous loop, not manual chaining | 4h |
| P0 | Fix apple foundation example | First target app; must demonstrate continuous loop | 3h |
| P1 | Implement Thread + Beat ontology | Core ontology gap; design doc describes it, code doesn't | 6h |
| P1 | Implement real scoring/pruning | Required for "hundreds of actors, threads scored" | 4h |
| P1 | Move `Situation` to resource | Archetype pollution; query cache invalidation | 2h |
| P1 | Add idle/sleep to `HarnessLoop` | Efficiency for hundreds of dormant actors | 3h |
| P1 | Add `Stream` subscription to `EventChannel` (ecsly) | Fix broken `forEach` snapshot pattern | 4h |
| P2 | Multi-actor coordination (`AddressedTo`, `PrivateToActor`, `DerivedFrom`) | a2a, self-reflection, isolation | 6h |
| P2 | Migrate core example to ECS | Old `AIWorld` API is deprecated | 4h |
| P2 | Deprecate `agent.dart` old API | Remove duplication | 2h |
| P3 | Multi-world (rich vs projection) | Bigger architectural change | 8h |
| P3 | Ink/Yarn-style narrative runner | Deeper narrative structure | 8h |

---

## 8. Design Invariants (Must Hold)

From `discussion.md` L657-666:

1. LLMs are called only on explicit Agency. Never in mechanical systems.
2. Projection is always a cinematic cut, never a history dump.
3. Structural mutation happens only through command queue + flush.
4. The runtime can sleep. Idle is first-class.
5. Action mechanisms (LLM router, User, ...) are swappable per Actor at runtime.
6. Parallelism is bounded and flush remains the coherence point.
7. Tool call parsing is backend-specific, not ECS-level.
8. Use native ecsly API; only add custom patterns when ecsly lacks a feature.
9. The loop never blocks on a single LLM call. Multiple actors' LLM calls run concurrently.
10. `asyncParallel` systems in the sync executor are fire-and-forget by design — use `runSchedule`, not `runScheduleAsync`.

---

## 9. Open Questions / Doubts

| # | Question | Status | Notes |
|---|---|---|---|
| Q1 | Should `Situation` be a resource or a separate projection world? | Open | Resource is simpler for MVP. Multi-world is Phase 2. |
| Q2 | Should tool execution be synchronous or async within `ProcessResponses`? | Decided | Synchronous for MVP. Async tracked via `PendingToolExecutionsResource`. |
| Q3 | How to handle the `ToolCall` name collision (event payload vs. Beat component)? | Decided | Rename Beat component to `BeatToolCall`. |
| Q4 | Should `HarnessLoop` modify `EcsFixedLoop` or wrap it? | Decided | MVP: wrap it with non-blocking tick. Phase 2: delegate to ecsly native async. |
| Q5 | How does the `HarnessLoop` handle concurrent LLM calls? | Decided | `ActorAct` dispatches all calls concurrently (fire-and-forget via sync executor's `asyncParallel` mode). `ProcessResponses` processes whatever arrived on each tick. |
| Q6 | Should `Thread` and `Beat` be in `agent_plugin.dart` or a new `narrative.dart`? | Decided | New file `narrative.dart` for clarity. |
| Q7 | How to handle User actors (not LLM)? | Open | `Actor` needs an `ActionMechanism` component (LLM / User / Other). |
| Q8 | How to handle backend-specific tool call parsing? | Decided | `ModelRuntime` or `ToolCallParser` strategy handles it. ECS layer receives parsed `ToolCall`s. |
| Q9 | Should we fix ecsly async or work around it in `EcsFixedLoop`? | Decided | Fix ecsly. Use `runSchedule` (sync path) which already does fire-and-forget for `asyncParallel`. |
| Q10 | How to handle idle/sleep with concurrent in-flight LLM calls? | Open | `canSleep()` checks `AwaitingResponse` count. Sleep only when zero. |
| Q11 | Should `EventChannel` get a `Stream` subscription API? | Open | Phase 2 goal. MVP uses polling via `handler.processPending(world)`. |

---

## 10. Progress Tracker

### Phase 0: Stabilize

- [ ] 0.1 Fix `processResponsesSystem` tool race
- [ ] 0.2 Fix `Agency` lifecycle (add `AwaitingResponse`)
- [ ] 0.3 Move `Situation` to `ProjectionResource`
- [ ] 0.4 Fix `EcsFixedLoop` async handling (use `runSchedule` not `runScheduleAsync`)
- [ ] 0.5 Create `HarnessLoop` (non-blocking, concurrent)
- [ ] 0.6 Fix apple foundation example to use `HarnessLoop`
- [ ] 0.7 Move tool call parsing to handler layer
- [ ] 0.8 Add tests for Phase 0 fixes

### Phase 1: Ontology

- [ ] 1.1 Create `narrative.dart` with Thread + Beat components
- [ ] 1.2 Implement graph-forming systems (spawnThread, startBeat, appendToBeat, completeBeat)
- [ ] 1.3 Implement real scoring/pruning systems
- [ ] 1.4 Register new components in `AgentPlugin`
- [ ] 1.5 Add tests for Thread/Beat systems

### Phase 2: Continuous Loop

- [ ] 2.1 Add idle/sleep to `HarnessLoop`
- [ ] 2.2 Add async completion tracking (pending agency/tool counters)
- [ ] 2.3 Add tests for idle/sleep behavior
- [ ] 2.4 Add `Stream` subscription to `EventChannel` (ecsly)

### Phase 3: Polish

- [ ] 3.1 Migrate core example to ECS `HarnessLoop`
- [ ] 3.2 Deprecate `agent.dart` old API
- [ ] 3.3 Add multi-actor coordination components
- [ ] 3.4 Add tests for multi-actor scenarios

### Phase 4: Advanced (Future)

- [ ] 4.1 Multi-world (rich world vs projection world)
- [ ] 4.2 Ink/Yarn-style narrative runner
- [ ] 4.3 Projection refinement (green-screen, visibility rules)
- [ ] 4.4 Multi-world CRDT sync

---

## 11. File Map

```
lib/src/agent/
├── agent.dart              # OLD API (AIRuntime, AIWorld, Agent) — DEPRECATE
├── agent_plugin.dart       # ECS plugin: components, systems, schedules — MODIFY
├── discussion.md           # Design doc — REFERENCE
├── tool_call_parser.dart   # Tool tag parsing — MOVE to handler layer
├── structured_output/      # Schema bundles — KEEP
├── narrative.dart          # NEW: Thread, Beat, graph-forming systems
├── harness_loop.dart       # NEW: HarnessLoop (non-blocking, concurrent)
├── PLAN.md                 # This file
└── agency_lifecycle.dart   # NEW: AwaitingResponse, agency rules (Phase 1)

test/
├── agent_harness_test.dart # Existing tests — EXTEND
├── narrative_test.dart     # NEW: Thread/Beat tests
└── harness_loop_test.dart  # NEW: Continuous loop tests

ecsly/ (separate repo)
├── lib/src/systems/system_executor.dart  # Already correct — sync executor does fire-and-forget
├── lib/src/events/event_channel.dart     # ADD: Stream subscription API (Phase 2)
└── lib/src/systems/schedule.dart         # Already correct — runSchedule vs runScheduleAsync

ecsly_app/ (separate repo)
└── lib/src/ecs_loop.dart  # FIX: use runSchedule instead of unawaited(runScheduleAsync)
```

---

## 12. MoE Synthesis Notes

### ECS Runtime Expert findings
- ecsly's sync executor (`_executeGroup`) already does fire-and-forget for `asyncParallel` systems — calls `desc.system(world)` without awaiting, discards the Future.
- `EcsFixedLoop` uses `unawaited(world.runScheduleAsync(name))` which goes through the async executor (`_executeGroupAsync`) that DOES await via `Future.wait` — wrong path.
- Fix: use `world.runSchedule(name)` (sync path) for all schedules.
- `EventChannel` has no subscription mechanism — `forEach` is snapshot-only.
- `ecsly_async_parallel` job system is for CPU-bound isolate work, not I/O-bound LLM calls.

### Concurrency & Multiplayer Expert findings
- Fire-and-forget is possible but requires in-flight tracking to prevent double-dispatch.
- `PendingLLMCall` component per actor prevents re-acting on the same actor.
- World destruction while LLM calls in-flight is dangerous — needs cancellation tokens.
- Backpressure needed for hundreds of actors.
- Idle/sleep must continue ticking while LLM calls are in-flight.

### ECS Architecture Skeptic findings
- The `actorActSystem` is already designed for fire-and-forget — it sends events and yields.
- The real problem is `EcsFixedLoop` using the wrong async path (`runScheduleAsync` instead of `runSchedule`).
- `actorActSystem` should be synchronous (remove `async`, remove `await Future.delayed`).
- The `EventChannel.forEach` subscription bug is the real blocker — the handler can't see events sent after registration.
- The simplest fix: make `actorActSystem` sync, add event subscription to `EventChannel`, let the host drive LLM calls.
