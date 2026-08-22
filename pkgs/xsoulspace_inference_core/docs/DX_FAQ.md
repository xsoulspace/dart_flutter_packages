# Agent Harness — DX FAQ

> How to work with the harness day to day: the vocabulary and the loop you will
> actually drive. The _why_ lives in `DESIGN_FAQ.md`; this file is the _how_.

## Terminology — say the right word

We deliberately named two things differently to stop confusing them:

- **projection** — the _act_ of casting a ray from a subject+viewpoint and
  collecting what it hits.
- a **cut** (a.k.a. the "cue") — the _output frame_, one fixed shot of the world
  handed to a model. In code this is the `Situation`.

So: you _project_ for an actor, and the actor receives a _cut_. "Memory" is never
an independent store you maintain — it is just _"project a past I'm entitled to"_.

## Tools: define once with structured schema, reuse everywhere

A tool is a `ToolDef`. Build it with a structured `SchemaBundle` (`FM.object` /
`FM.prop`), never a random JSON map:

```dart
final readTool = ToolDef.structured(
  name: const ToolName('read'),
  description: 'Read a file',
  parameters: SchemaBundle(
    root: FM.object('read', properties: () => [FM.prop('path', FM.string())]),
  ),
  execute: (args) async {
    final params = jsonDecodeMapAs(args);
    return File(jsonDecodeString(params['path'])).readAsString();
  },
);
```

Shared real tools live in `lib/src/agent/tools/fs_tools.dart` —
`fsTools(FsToolsRoot('/path/to/jail'))` (`read`, `write`, `list_dir`). The
suite is jailed: every path is resolved against the root and rejected if it
escapes. Always pass an explicit root; never expose unrestricted filesystem
access to a model. These tools require `dart:io` (CLI/server/desktop only).
A tool result is stored **structurally** on its beat as `ToolResultContent`
(name + typed output); the short `TextContent` on the same beat is only for
projection/indexing, never the source of truth.

There is **no `ScenarioTool`** — `Scenario.tools` is a `List<ToolDef>`.

## The two things you reach for

### 1. The facet index — `FacetIndex`

The reader-side index that makes projection a ray instead of a scan.

| You want                         | Method                                           |
| -------------------------------- | ------------------------------------------------ |
| Index a beat under some keywords | `indexBeat(world, beat, ['parser', 'brackets'])` |
| Find beats for a keyword         | `index.beatsFor(['parser'])`                     |
| The keywords currently on a beat | `index.keywordsFor(beat)`                        |

Beats are indexed when they are written; projection reads the index
functionally. You do not maintain a per-actor list — you maintain edges + index
entries.

### 2. The projection system

`projectSituationSystem` runs in the `Project` schedule. For each actor holding
agency it:

1. Ray-traces the graph — keyword hits via `FacetIndex` ∪ beats reachable from
   the actor's `ActorThreads`.
2. Ranks by relevance to the prompt; breaks ties by recency.
3. Fits the result into `ProjectionBudget.tokens` (default 4k).
4. Marks what was cut as **green-screen absences** so the model knows what it
   does _not_ see.

The result is a `Situation` — the cut. The actor entity never stores it; it is
re-derived each decision.

## Writing beats

```dart
final thread = spawnThread(world, actor, scene);
final beat = startBeat(world, thread, actor, BeatModalityEnum.text);
appendToBeat(world, beat, "the parser fails on nested brackets");
completeBeat(world, beat);
indexBeat(world, beat, ['parser', 'brackets']);
```

The beat is now in the graph and reachable by projection.

## Summarising is a deliberate transform, not housekeeping

To collapse a set of source beats into a `MemorySummary` (a first-class beat):

```dart
final summary = summarizeThread(world, thread, [beatA, beatB]);
// summary stays in `thread` (BelongsToThread),
// links its sources (SummarizesBeats),
// and is indexed under the union of source keywords.
```

The harness never summarises automatically. If you do not call it, nothing gets
compacted.

## Driving the loop

### By hand (tests)

```dart
world.runSchedule('AgencyGrant'); // grant agency to actors with decisions
world.flush();
world.runSchedule('Project');      // build the cut (Situation) for each
await world.runScheduleAsync('ActorAct');        // dispatch generation requests
world.runSchedule('ProcessResponses'); // handle responses; write indexed beats
world.runSchedule('Mechanical');   // execute tools, score/prune threads
world.runSchedule('Narrative');    // finalize partials, advance the story
```

### Headless CLI / server

`HarnessLoop.runUntilIdle()` drives all schedules until the world is idle —
no open decisions, no awaiting responses, no in-flight tasks:

```dart
final loop = HarnessLoop(world: world);
await loop.runUntilIdle(); // optional maxTicks guard against runaway worlds
// read response beats from the graph
```

This is the entry point for pi/codex-style CLIs and server-side worlds:
spawn actors with `OpenDecision`s, call `runUntilIdle()`, read beats.

## Failure guarantees

The harness never hangs on a failing backend:

- A throwing or hanging tool produces an error `ToolResultEvent` (after
  `AgencyPolicy.taskTimeout`) and frees the actor.
- A missing or crashed handler fails fast with an error response.
- Failed/empty responses retry up to `AgencyPolicy.maxRetries`, then the
  decision is dropped.
- In-flight generation tasks are failed by a timeout sweeper after
  `AgencyPolicy.taskTimeout` (default 5 min; `Duration.zero` disables).

## Escalation tiers

Models carry an escalation rank: `Model(tier: n)` — higher tier = stronger.
An actor with `OpenDecision(escalate: true)` routes to the lowest-tier model
strictly above its current binding. No higher tier → keeps its own model.

## Testing without an LLM

Every part except _write a beat_ is deterministic graph logic. Use a
`MockGenerationHandler` (see `test/support/agent_harness_support.dart`) to play
every schedule with no real model. Scripted mutations drive projection, agency,
escalation, tool calls, and thread scoring end to end.

## Pitfalls

- **Do not** model memory as a list on the actor. Link the actor to threads,
  then project. If something smells like a compaction policy, it is the old
  scalar primitive — delete it, don't extend it.
- **Do not** hand raw history to the model. Only the projected `Situation`
  (the cut) reaches the model in `actorActSystem`.
- **Do not** auto-summarise in a schedule. Producing a `MemorySummary` is an
  explicit graph transformation you request.
