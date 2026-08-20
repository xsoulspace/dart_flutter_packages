# Agent Harness — DX FAQ

> How to work with the harness day to day: the vocabulary and the loop you will
> actually drive. The *why* lives in `DESIGN_FAQ.md`; this file is the *how*.

## Terminology — say the right word

We deliberately named two things differently to stop confusing them:

- **projection** — the *act* of casting a ray from a subject+viewpoint and
  collecting what it hits.
- a **cut** (a.k.a. the "cue") — the *output frame*, one fixed shot of the world
  handed to a model. In code this is the `Situation`.

So: you *project* for an actor, and the actor receives a *cut*. "Memory" is never
a thing you maintain — it is just *"project a past I'm entitled to"*.

## The two things you reach for

### 1. The facet index — `FacetIndex`

The reader-side index that makes projection a ray instead of a scan.

| You want | Method |
| --- | --- |
| Index a beat under some keywords | `indexBeat(world, beat, ['parser', 'brackets'])` |
| Find beats for a keyword | `index.beatsFor(['parser'])` |
| The keywords currently on a beat | `index.keywordsFor(beat)` |

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
   does *not* see.

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

`HarnessLoop` runs the schedules in order and sleeps when nothing is pending
(no `OpenDecision`, no `Agency`, no `AwaitingResponse`, no in-flight tasks).
You can drive the schedules by hand for tests:

```dart
world.runSchedule('AgencyGrant'); // grant agency to actors with decisions
world.runSchedule('Project');      // build the cut (Situation) for each
await world.runScheduleAsync('ActorAct');        // dispatch generation requests
world.runSchedule('ProcessResponses'); // handle responses; write indexed beats
world.runSchedule('Mechanical');   // execute tools, score/prune threads
world.runSchedule('Narrative');    // finalize partials, advance the story
```

## Testing without an LLM

Every part except *write a beat* is deterministic graph logic. Use a
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