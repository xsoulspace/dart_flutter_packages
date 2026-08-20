# Agent Harness — Design FAQ

> Why the harness is shaped this way. The **why** behind the graph-native
> model, projection-as-ray-tracing, and facets. If this drifts from the code,
> fix the code or fix this doc — never both silently.

## 1. "Memory" is not the primitive

Early versions modeled an actor as having a *history to compress*: a per-actor
fragment list with a compaction policy that collapsed old raw fragments into
summaries to stop the list from growing. That is the scalar/linear frame dressed
up in ECS, and it was wrong for three reasons.

1. **Beats grow like a book.** They do not "need compaction" in the general
   sense. Compaction made sense only because memory was framed as a per-actor
   list that must shrink.
2. **The actor's reality *is* the situation you hand it.** "Memory" is just one
   flavor of projection — *project a past I'm entitled to*. There is no separate
   memory store to maintain.
3. **You never "decide what to keep in memory"; you decide what to render.**
   Projection is ray-tracing, not summarization.

The scalar narrative is gone. The actor stores *links* (which threads it belongs
to) and a *facet index*; everything the actor sees is re-derived on demand.

## 2. Projection is ray-tracing, not summarization

You cast a ray from the queried frame:

```
(actor + scene + props + co-actors + question/keywords)
```

and collect only the beats that ray hits. Everything else is literally dark.
There is no "memory of what to keep" — there is only the **cut** (the output
frame) and **green-screen** (explicit statements of what the model does *not*
see).

The projection machinery is **one generic thing**, parameterized by subject +
viewpoint. You can project for an actor, a prop, a scene, a beat, a thread, or a
subset. A "subject" is just an entry point into the graph.

## 3. The facet index makes the ray O(beats-returned)

Ray-tracing is only as good as what you can query. Without an index, projecting
would scan every beat — O(all-beats). The `FacetIndex` is the reverse, reader-side
structure that makes this fast and bounded:

- `keyword → beats` for the haystack hit.
- `beat → keywords` for the beat's own facets.

Projection becomes: hit the index, walk edges to broaden, rank, and fit to a
token budget.

## 4. Situation is the actor's reality

A `Situation` is the output frame handed to the model: the local question, props
in frame, co-present actors, the projected (budget-limited) beats, and the green-screen absences. It is a *derived view*, never a stored per-actor list. Nothing
in the actor entity owns "the actor's memory"; the actor owns only its graph
links, and the situation is re-computed each decision.

`ContextFragment`/`ActorMemoryRef` was the old plan for this; it was replaced by
a **derived projection result** (the `Situation`, the "cue"). The machine is not
stored on the entity — it is *read functionally* from the world.

## 5. Summary is a beat kind, not a policy

A `MemorySummary` is a first-class beat, exactly like text/thought/toolCall.
It aggregates content from its source beats and links back to them
(`SummarizesBeats`). It is only produced by a **deliberate, requested graph
transform** (`summarizeThread`) — the harness never summarises automatically as
housekeeping.

So say we deleted:

- `ActorRuntimeMemories`, `ActorMemoryRef`, `MemoryCompactionPolicy`,
  `ContextFragmentType`, and the automatic compaction system.

What remains is one projection system over a thread/beat graph, with a facet
index, plus optional, explicit summaries as graph nodes. Same node/edge
machinery everywhere.

## 6. Design invariants

- A tiny local model (2–4k context) is genuinely useful because the harness does
  the heavy lifting; the model is a replaceable reasoning primitive.
- Projection is bounded and **measured**; exceeding the budget fails the
  benchmark.
- Agency is granted only when a real decision is open; everything else is
  mechanical and never touches an LLM.
- The loop is continuous, concurrent, and sleeps when idle.
- **Tools are structured and first-class.** A tool is a `ToolDef` with a
  `SchemaBundle` schema; a tool result is stored on its beat as
  `ToolResultContent` (name + typed output), not a stringified blob. Shared real
  tools live in `lib/src/agent/tools.dart`.

## 7. Non-goals

- **Not** a per-actor memory log with a pruning policy.
- **Not** conversation-centric: dialogue is one allowed action (thinking,
  planning, tool use, research) rather than the core mode.
- **Not** a monolith: the core stays UI-agnostic; UI/CLI/TUI/Flutter are thin
  hosts over the same world.