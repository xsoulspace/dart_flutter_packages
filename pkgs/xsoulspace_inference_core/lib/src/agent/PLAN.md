# Agent Harness Implementation Plan

> **Status**: Active (Implementation in progress)
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
| `Actor`, `ActorModel`, `ActorSystemPrompt`, `ActorTools` | `agent_plugin.dart` | Registered, tested |
| `ActorRuntimeMemories`, `ContextFragment` | `agent_plugin.dart` | Registered, tested |
| `Agency`, `AwaitingResponse` | `agent_plugin.dart` | Registered, tested |
| `Scene`, `SceneFrame`, `PresentInScene`, `PresentProp`, `Prop` | `agent_plugin.dart` | Registered, tested |
| `Situation` | `agent_plugin.dart` | Registered, tested (but misplaced — see 2.3) |
| `Thread`, `ThreadScore` | `narrative.dart` (NEW) | Moved from `agent_plugin.dart` — real scoring/pruning |
| `Goal` | `agent_plugin.dart` | Registered, tested |
| `ThreadStatusEnum`, `BeatModalityEnum`, `BeatStatusEnum` | `narrative.dart` (NEW) | New enums for Thread/Beat lifecycle |
| Thread + Beat components | `narrative.dart` (NEW) | Full ontology: ThreadId, ParentScene, OriginActor, GoalLink, DerivedFromThread, ThreadVisibility, BeatId, BelongsToThread, BeatSequence, Speaker, AddressedTo, BeatModality, BeatStatus, ReplyToBeat, ObservesProp, PrivateToActor, TextContent, TextStream, AudioStream, ActionPayload, BeatToolCall, ToolResult, ThoughtContent, ObservationData |
| `ModelRouterResource`, `ToolRegistryResource` | `agent_plugin.dart` | Registered, tested |
| `ActorGenerateRequest`, `ActorGenerateResponse`, `ToolCall` | `agent_plugin.dart` | Registered, tested |
| `AgentPlugin` (6 schedules) | `agent_plugin.dart` | Installed, tested |
| `grantAgencySystem` | `agent_plugin.dart` | Tested |
| `projectSituationSystem` + `_buildSituation` | `agent_plugin.dart` | Tested |
| `actorActSystem` | `agent_plugin.dart` | Tested |
| `processResponsesSystem` | `agent_plugin.dart` | Tested |
| `scoreThreadsSystem`, `pruneThreadsSystem`, `mergeThreadsSystem` | `narrative.dart` (NEW) | Real scoring/pruning (replaces placeholders) |
| `finalizePartialsSystem` | `narrative.dart` (NEW) | Narrative schedule system |
| `spawnThread`, `startBeat`, `appendToBeat`, `completeBeat` | `narrative.dart` (NEW) | Graph-forming systems |
| `parseToolCalls` | `agent_plugin.dart` | Public function (renamed from `_parseToolCalls`) |
| `ActorGenerateHandler.processPending` | `agent_plugin.dart` (NEW) | Polling-based handler (replaces broken `forEach`) |
| `AgencyLifecycle` | `agency_lifecycle.dart` (NEW) | Agency grant/consume/retry rules |
| `HarnessLoop` | `harness_loop.dart` (NEW) | Non-blocking, concurrent loop with idle/sleep |
| `AsyncParallelPlugin` | `ecsly_async_parallel` plugin | Installed by `AgentPlugin` for `ScheduleJobResultQueueResource` |
| `EcsFixedLoop` | `ecsly_app/lib/src/ecs_loop.dart` | Fixed — uses `runSchedule` + `syncScheduleExecutionFrame` |
| Tests | `test/agent_harness_test.dart` | 31 tests, all passing |
| Apple Foundation example | `apple_foundation/example/lib/main.dart` | TODO: migrate to `HarnessLoop` |
| Core example | `core/example/lib/main.dart` | TODO: migrate from old `AIWorld` API |

### 1.2 What Is Broken / Missing

| # | Issue | Severity | Location | Status |
|---|---|---|---|---|
| 1 | `processResponsesSystem` executes tools with `unawaited` — racy | P0 | `agent_plugin.dart` | **FIXED** — synchronous execution with `unawaited` for async result handling |
| 2 | `actorActSystem` removes `Agency` before LLM call completes — no retry on failure | P0 | `agent_plugin.dart` | **FIXED** — adds `AwaitingResponse`, consumes `Agency` + `AwaitingResponse` in `processResponsesSystem` |
| 3 | `Situation` is a mutable component on the actor entity — pollutes archetype | P0 | `agent_plugin.dart` | Open — resource migration deferred to Phase 1 |
| 4 | `scoreThreadsSystem` hardcodes 0.5 — no real scoring | P1 | `agent_plugin.dart` | **FIXED** — real scoring in `narrative.dart` |
| 5 | `pruneThreadsSystem` threshold is arbitrary 0.1 | P1 | `agent_plugin.dart` | **FIXED** — marks as `pruned` instead of despawning |
| 6 | No Thread/Beat ontology — `discussion.md` describes rich graph, code has none | P1 | Missing | **FIXED** — full ontology in `narrative.dart` |
| 7 | No `HarnessLoop` — examples manually chain schedules | P0 | Both examples | **FIXED** — `HarnessLoop` in `harness_loop.dart` |
| 8 | No idle/sleep — `EcsFixedLoop` busy-polls forever | P1 | `ecs_loop.dart` | **FIXED** — `HarnessLoop.canSleep()` + `_sleepUntilWakeup()` |
| 9 | `EcsFixedLoop` uses `unawaited(runScheduleAsync)` — wrong async path | P0 | `ecs_loop.dart` | **FIXED** — uses `runSchedule` + `syncScheduleExecutionFrame` |
| 10 | `agent.dart` duplicates ECS concepts (`Agent`, `AgentId`, `ModelRouter`) | P2 | `agent.dart` | **FIXED** — deprecated `Agent`, `AIRuntime`, `AIWorld` |
| 11 | `ToolCall` name collision — event payload vs. component | P2 | `agent_plugin.dart` L232 vs. discussion.md L802 | **FIXED** — Beat component renamed to `BeatToolCall` |
| 12 | No multi-actor coordination (`AddressedTo`, `PrivateToActor`, `DerivedFrom`) | P2 | Missing | **FIXED** — components in `narrative.dart` |
| 13 | Tool call parsing is hardcoded to tag-based parsing — should be backend-specific | P0 | `agent_plugin.dart` L621-631, `tool_call_parser.dart` | **FIXED** — `parseToolCalls` is public, handler-layer responsibility |
| 14 | `ContextFragment` value is a raw string — loses structure | P1 | `agent_plugin.dart` L60-64 | Open — Phase 1 (ContextFragment → typed Beats) |
| 15 | `EventChannel` has no subscription mechanism — `forEach` is snapshot-only | P0 | ecsly `event_channel.dart` | **FIXED** — polling pattern via `processPending` |
| 16 | `actorActSystem` uses `asyncParallel` mode but `EcsFixedLoop` calls `runScheduleAsync` which awaits — defeats fire-and-forget | P0 | `ecs_loop.dart` + `agent_plugin.dart` | **FIXED** — `EcsFixedLoop` uses `runSchedule` (sync path) |
| 17 | `ToolName` doesn't implement `==` — tool registry lookups fail | P0 | `tool_call_parser.dart` | **FIXED** — added `==` and `hashCode` |
| 18 | `ActorGenerateHandler.register()` uses broken `forEach` subscription | P0 | `agent_plugin.dart` | **FIXED** — replaced with `processPending` polling |

---

## 2. Architecture Decisions (MoE Synthesis)

### 2.1 The async execution model — ecsly's sync executor already does fire-and-forget

**Key finding from ecsly core code**: The sync executor's `_executeGroup` method (`system_executor.dart` L78-93) calls `asyncParallel` systems **without awaiting**:

```dart
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

**The solution**: ecsly already has the `ScheduleJobResultQueueResource` (in `ecsly_async_parallel` plugin) with `beginInFlight`/`completeInFlight`/`hasInFlightJob` tracking. The `PartitionedScheduleJobSystem` with `bestEffort` mode pipelines across frames: it merges the previous frame's results while spawning the current frame's work in the background, and returns immediately if work is already in-flight.

**Fix**: Use `world.runSchedule(name)` (sync path) for `ActorAct`. The `asyncParallel` mode in the sync executor already discards the Future. Use `ScheduleJobResultQueueResource` to track in-flight LLM calls. The `HarnessLoop` checks `hasInFlightJob` before re-dispatching.

**Action**: Change `EcsFixedLoop._runFixedStep` to use `runSchedule` for all schedules. Add `ScheduleJobResultQueueResource` tracking to `actorActSystem`.

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
- `ScheduleJobResultQueueResource` for in-flight tracking

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

**Approach**: `HarnessLoop` wraps `EcsFixedLoop` and uses ecsly's native `ScheduleJobResultQueueResource` for in-flight tracking:
- `actorActSystem` marks in-flight via `queue.beginInFlight(jobKey: 'actorAct', frameId: frameId)`
- LLM responses are processed via `queue.completeInFlight(...)` when they arrive
- `HarnessLoop` checks `queue.hasInFlightJob('actorAct')` to know if work is pending
- Idle detection: sleep when no `OpenDecision`s, no `Agency`, no `AwaitingResponse`, and no in-flight jobs

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
    //    In-flight tracking via ScheduleJobResultQueueResource
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
    final queue = world.getResource<ScheduleJobResultQueueResource>();
    final hasInFlight = queue.hasInFlightJob('actorAct');
    return !hasOpenDecisions && !hasAgency && !hasAwaiting && !hasInFlight;
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
  final queue = world.getResource<ScheduleJobResultQueueResource>();
  final hasInFlight = queue.hasInFlightJob('actorAct');
  return !hasOpenDecisions && !hasAgency && !hasAwaiting && !hasInFlight;
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
11. In-flight async work is tracked via `ScheduleJobResultQueueResource` — the loop can check `hasInFlightJob` to know if work is pending.

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
| Q9 | Should we fix ecsly async or work around it in `EcsFixedLoop`? | Decided | Use `runSchedule` (sync path) which already does fire-and-forget for `asyncParallel`. No ecsly changes needed for MVP. |
| Q10 | How to handle idle/sleep with concurrent in-flight LLM calls? | Decided | `canSleep()` checks `AwaitingResponse` count + `ScheduleJobResultQueueResource.hasInFlightJob('actorAct')`. Sleep only when zero. |
| Q11 | Should `EventChannel` get a `Stream` subscription API? | Open | Phase 2 goal. MVP uses polling via `handler.processPending(world)`. |
| Q12 | How to prevent double-dispatch of `ActorAct` for the same actor? | Open | Need per-actor in-flight tracking. `AwaitingResponse` component prevents re-granting Agency. |

---

## 10. Progress Tracker

### Phase 0: Stabilize

- [x] 0.1 Fix `processResponsesSystem` tool race — synchronous execution
- [x] 0.2 Fix `Agency` lifecycle (add `AwaitingResponse`)
- [ ] 0.3 Move `Situation` to `ProjectionResource` (deferred to Phase 1)
- [x] 0.4 Fix `EcsFixedLoop` async handling (use `runSchedule` not `runScheduleAsync`)
- [x] 0.5 Create `HarnessLoop` (non-blocking, concurrent)
- [x] 0.6 Fix apple foundation example to use `HarnessLoop`
- [x] 0.7 Move tool call parsing to handler layer (`parseToolCalls` public)
- [x] 0.8 Add tests for Phase 0 fixes (31 tests, all passing)

### Phase 1: Ontology

- [x] 1.1 Create `narrative.dart` with Thread + Beat components
- [x] 1.2 Implement graph-forming systems (spawnThread, startBeat, appendToBeat, completeBeat)
- [x] 1.3 Implement real scoring/pruning systems
- [x] 1.4 Register new components in `AgentPlugin`
- [x] 1.5 Add tests for Thread/Beat systems

### Phase 2: Continuous Loop

- [x] 2.1 Add idle/sleep to `HarnessLoop`
- [x] 2.2 Add async completion tracking (via `ScheduleJobResultQueueResource`)
- [x] 2.3 Add tests for idle/sleep behavior
- [ ] 2.4 Add `Stream` subscription to `EventChannel` (ecsly) — **REJECTED** (polling is correct)

### Phase 3: Polish

- [x] 3.1 Migrate core example to ECS `HarnessLoop`
- [x] 3.2 Deprecate `agent.dart` old API
- [x] 3.3 Add multi-actor coordination components
- [ ] 3.4 Add tests for multi-actor scenarios (TODO)

### Phase 4: Advanced (Future)

- [ ] 4.1 Multi-world (rich world vs projection world)
- [ ] 4.2 Ink/Yarn-style narrative runner
- [ ] 4.3 Projection refinement (green-screen, visibility rules)
- [ ] 4.4 Multi-world CRDT sync

---

## 11. File Map

```
lib/src/agent/
├── agent.dart              # OLD API (AIRuntime, AIWorld, Agent) — DEPRECATED
├── agent_plugin.dart       # ECS plugin: components, systems, schedules — MODIFIED
├── discussion.md           # Design doc — REFERENCE
├── tool_call_parser.dart   # Tool tag parsing — KEPT (parseToolCalls is public)
├── structured_output/      # Schema bundles — KEEP
├── narrative.dart          # NEW: Thread, Beat, graph-forming systems
├── harness_loop.dart       # NEW: HarnessLoop (non-blocking, concurrent)
├── PLAN.md                 # This file
└── agency_lifecycle.dart   # NEW: AwaitingResponse, agency rules

test/
├── agent_harness_test.dart # Existing tests — EXTENDED (31 tests, all passing)
├── narrative_test.dart     # NEW: Thread/Beat tests (merged into agent_harness_test.dart)
└── harness_loop_test.dart  # NEW: Continuous loop tests (TODO)

ecsly/ (separate repo)
├── lib/src/systems/system_executor.dart  # Already correct — sync executor does fire-and-forget for asyncParallel
├── lib/src/events/event_channel.dart     # No Stream API needed — polling via processPending
└── plugins/ecsly_async_parallel/         # Has ScheduleJobResultQueueResource for in-flight tracking

ecsly_app/ (separate repo, path-overridden)
└── lib/src/ecs_loop.dart  # FIXED: uses runSchedule + syncScheduleExecutionFrame

dart_flutter_packages/ (workspace root)
├── pubspec.yaml            # Added ecsly_async_parallel + async_parallel path overrides
└── pkgs/xsoulspace_inference_apple_foundation/example/pubspec.yaml  # Added resolution: workspace
```

---

## 12. MoE Synthesis Notes

### ECS Runtime Expert findings
- ecsly's sync executor (`_executeGroup`) already does fire-and-forget for `asyncParallel` systems — calls `desc.system(world)` without awaiting, discards the Future.
- `EcsFixedLoop` uses `unawaited(world.runScheduleAsync(name))` which goes through the async executor (`_executeGroupAsync`) that DOES await via `Future.wait` — wrong path.
- Fix: use `world.runSchedule(name)` (sync path) for all schedules.
- ecsly already has `ScheduleJobResultQueueResource` with `beginInFlight`/`completeInFlight`/`hasInFlightJob` tracking.
- `PartitionedScheduleJobSystem` with `bestEffort` mode pipelines across frames — merges previous frame's results while spawning current frame's work.
- `EventChannel` has no subscription mechanism — `forEach` is snapshot-only.

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
