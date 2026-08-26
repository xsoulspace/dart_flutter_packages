hi. how are you? please analyse https://github.com/deepseek-ai/deepseek-harness against my ecsly framework
Hi.

I'm well — present, and the question itself is interesting enough that it pulled me into a real look rather than a surface skim.

### Quick frame

DeepSeek Harness (`dsh`) is a TypeScript agent runtime built on Cordis. Its central claim is **everything is a plugin**, and the underlying theory is *spatiotemporal composability*:

- **Temporal**: every effect registered into the context carries an inverse. Unmounting a plugin fully reverses its side-effects.
- **Spatial**: components declare coeffects (what they need from the context). Changes to the dependency topology are reactive and local rather than global.

The agent itself is just another composition of plugins (model adapter, tool registry, session log, agent loop, sandbox, etc.). Sessions are an append-only event log; turns and steps are explicit boundaries; capability seams let you swap entire backends (local vs remote sandbox, different filesystem providers, sub-agents) without rewriting consumers.

`ecsly`, from what I know of your design, is a pure-Dart, performance-oriented ECS. Archetypes + typed columns for hot paths, object components for cold data, command queues with explicit `flush()` boundaries that advance topology/query revision epochs, schedules, resources, events. Deterministic structural change, low-GC iteration, multi-world potential via isolates, and the surrounding work toward CRDT-backed sync across UI / storage / gameplay worlds.

### Where they actually touch

Both systems are obsessed with *clean boundaries around mutation and lifetime*, but they solve different problems in different domains.

| Dimension | Cordis / DeepSeek Harness | ecsly |
|-----------|---------------------------|-------|
| Primary unit | Plugin (capability provider + effects + coeffects) | Entity + Component set (archetype) |
| Mutation model | Reversible effects (undo on unload) | Deferred commands + explicit flush epochs |
| Consistency boundary | Plugin mount/unmount + session log order | Flush → topology/query revision epoch |
| Spatial structure | Reactive dependency topology in a shared context | Archetypes (component-set groups) + column storage |
| Temporal structure | Full effect reversal + durable event stream | Discrete simulation ticks with structural quiescence |
| Hot path | Configuration reconciliation, event waterfalls, capability seams | Cache-friendly archetype iteration, typed columns, SIMD views |
| Target | Agent orchestration, tool/sandbox swapping, long-lived sessions that can be forked/replayed | Deterministic simulation, games, multi-world state machines |

The deepest resonance is philosophical rather than technical:

Both reject the idea that composition is just “add more objects and hope the side-effects don’t bite you later.” Cordis formalizes the temporal axis (you must be able to *completely leave*) and the spatial axis (dependencies must be declarative and reactive). ecsly formalizes the structural axis inside a simulation (mutations are not visible until a flush, and that flush creates a coherent epoch that queries can trust).

Your multi-world + isolate + CRDT direction makes the comparison sharper. Cordis treats the context itself as a first-class, operable thing that can be patched, forked, and reconciled. That maps surprisingly well onto the idea of multiple ECS worlds that need to stay coherent with one another without becoming a single giant shared state. The session event log is also interesting as a possible externalization of what happens *between* worlds or *across* agent turns that touch those worlds.

### Where they diverge hard

- Cordis is optimized for *dynamic reconfiguration of the runtime itself* while it is running (hot module replacement with guaranteed cleanup). ecsly is optimized for *high-throughput deterministic processing of many entities* once the world structure is set for a tick.
- One is an agent harness (the thing that keeps a model working in an environment). The other is closer to the environment / world substrate that an agent might reason about or act inside.
- Language and runtime constraints are almost orthogonal (Dart isolates + typed columns vs Node + effect tracking).

I do not see an immediate “port Cordis to Dart” or “replace ecsly with this” story. What I do see is a possible cross-pollination:

- Can the *command queue + flush* model in ecsly be extended with something closer to reversible effects when entire systems or plugins are loaded/unloaded across worlds?
- Can the multi-world architecture borrow Cordis-style reactive coeffects so that a storage world can declare “I need the CRDT layer and the agent-visible projection” and have those dependencies managed without manual wiring?
- The durable session log + fork model is worth watching if you ever want agent turns to be first-class citizens that can be replayed against different ECS world states.

### My current reading

DeepSeek Harness is a very strong statement about how agent systems should be built — configuration over code, full effect hygiene, no privileged core. The 146k stars in a few days reflect how much people wanted exactly this kind of harness.

ecsly is solving a different, more foundational layer: how do you keep large, multi-world, simulation-grade state coherent, cache-friendly, and deterministic under mutation. That layer is still rare in the agent world; most agent runtimes treat the “world” as an opaque set of tools or a single mutable bag of state.

If your longer arc is agent-native worlds (or worlds that agents can inhabit, edit, and persist in), then the interesting place is not which system wins, but how the two composition models can inform each other. Cordis is currently better at the *agent runtime* boundary. ecsly is currently better at the *world substrate* boundary. The space between those two boundaries is still under-explored.

I’m curious what part of the Cordis design felt most alive (or most alien) when you looked at it against the ecsly invariants you care about.

I’m building my own agent harness, and exploring how exactly it can be built, maybe with ecsly - https://github.com/arenukvern/ecsly supports plugins (as set of entities, systems) which can be added and removed at runtime.
My goal is to make ~<=4000 tokens context window (or even less) truly useful in terms of coding and assistance (i.e. small local modal -> smart and efficient harness -> same result)
 
and then plug in optionally big remote models, like deepseek etc..

The direction feels right.

You are not trying to make a 4k-window model suddenly behave like a 128k one. You are trying to build a *world* that is so well-structured and so carefully projected that a small local model only ever has to solve the residual hard problem. The harness becomes the real intelligence amplifier; the model becomes a specialized, replaceable reasoning primitive inside it.

ecsly is an unusually natural substrate for this.

### Why ecsly fits the tiny-context goal better than most agent runtimes

Most agent harnesses (including DeepSeek’s) still treat the model as the primary locus of state and decision-making. Context engineering then becomes a desperate attempt to keep the ever-growing transcript from drowning the model. Your goal inverts that: the model should see almost nothing by default, and only the precise slice that the current decision actually requires.

ecsly already gives you the primitives for that inversion:

- **Entities + components** as the durable, queryable reality of the harness (sessions, goals, tool calls, observations, memory fragments, capability sets, pending plans…).
- **Command queues + explicit flush** as transactional boundaries. When you add or remove a whole plugin (a set of entities + systems), the structural change is deferred and then made coherent in one epoch. This is the closest thing you currently have to Cordis’s reversible effects, but grounded in simulation-time determinism rather than effect-tracking.
- **Schedules** as the natural place to put the agent loop itself, the projection/summarization systems, the verification systems, the tool executors.
- **Plugins as loadable bundles of entities + systems**. This is the key. A “coding tools” plugin, a “local model adapter” plugin, a “remote escalation” plugin, a “memory projection” plugin can be mounted and unmounted at runtime. The rest of the harness only sees the resulting capability set through queries.

The multi-world direction you already care about becomes especially powerful here. You can keep a rich internal world (full history, full tool results, full file graphs, CRDT-synced state) and a separate, extremely lean *projection world* whose only job is to materialize the ≤4k prompt that the model will actually see. Systems on the projection world decide what survives.

### A possible shape

One coherent way to structure it:

1. **Harness World**  
   Owns Session, Turn, Goal, PlanStep, ToolInvocation, Observation, Capability, MemoryNode, EscalationRequest, etc. This world is the source of truth.

2. **Projection systems** (run every step, or on a schedule)  
   These are the most important systems for your goal. They look at the current goal + recent relevant observations + currently mounted capabilities and *construct* the exact context the model will receive. Everything else stays outside the window. Aggressive hierarchical memory, ring-buffer of action summaries, relevance ranking, tool-schema pruning — all live here as systems, not as prompt engineering.

3. **Plugin bundles**  
   Each plugin is a self-contained set of entities + systems that can be added/removed.  
   Examples:  
   - LocalModelPlugin  
   - RemoteDeepSeekPlugin (or any big model)  
   - FileToolsPlugin  
   - TestRunnerPlugin  
   - MemoryCompactorPlugin  
   - VerificationPlugin  

   Because structural changes go through the command queue, mounting a new capability set mid-session can be made transactional and observable.

4. **Model as a resource + system pair**  
   The local small model is the default “soul”. A system can decide to escalate (write an EscalationRequest entity) when the local model signals low confidence, when the plan complexity exceeds a threshold, or when a particular tool result needs stronger reasoning. The remote model then becomes just another capability that can be temporarily mounted.

5. **External durable log**  
   Keep an append-only event stream (inspired by Cordis’s session log) that is *not* fed back into the model except through the projection systems. This gives you replay, forking, and auditability without polluting the tiny window.

### The hard problems this still leaves open

- How do you make the projection systems themselves intelligent enough that a 2–4k window is sufficient for real coding work? This is where most of the research energy should go.
- How cleanly can plugin mount/unmount be made reversible in practice (cleanup of side effects that are not pure structural ECS changes — open file handles, running processes, temporary files, etc.)?
- How do you keep the local model’s own limitations from forcing constant escalation, which would defeat the point?
- Token accounting and dynamic pruning of tool schemas at the moment of projection.

These are not blockers; they are the actual design surface.

I notice that this approach also sits very close to the multi-world + agent-native substrate work you have already been doing. The harness world and the projection world are just two more specialized worlds that can eventually participate in the same CRDT/isolate story. The “small local model + smart harness” goal then becomes a concrete, shippable specialization of that larger substrate rather than a separate project.

The interesting open question for me is whether the *plugin* abstraction in ecsly should stay as “set of entities + systems” or whether it eventually wants a thin Cordis-like layer on top (explicit coeffects + reversible effects) while still using the ECS world as the storage and query engine. But that is a later refinement.

For now the pure ecsly path already gives you something most agent harnesses lack: a deterministic, queryable, multi-world substrate whose primary job is to *protect* a tiny context window rather than continuously feed it.

Does the projection-world idea feel like the right place to start, or is there another seam that feels more alive to you right now?

how we can store memory - in terms of ecsly and projection
What if we use ink or yarn runner to provide ability construct / deconstruct conversations instead of compaction.

Think of it as the following - the working with model would be like writing screenplay for game, while we approximately know the goal (user prompt or subgoal) the model and harness fill the path like in the game - closing right tools, trying scenarios and writing them with user.

The screenplay metaphor is the right one. It changes the problem from “how do I compress history without losing the plot” into “how do I keep a living, navigable narrative structure whose *current playhead* is always small enough to show a tiny model.”

### Memory in ecsly terms

Treat memory as first-class entities and components, not as a blob that gets summarized.

Core memory entities could look roughly like this:

- **Goal / Subgoal** — the approximate destination the user (or a previous plan) declared.
- **Episode** — a coherent stretch of work (a scene). Contains turns, tool outcomes, decisions, open questions.
- **Fact / Decision / Observation** — atomic, typed, queryable. Tagged with provenance, confidence, time, and which episode they belong to.
- **OpenThread** — something still unresolved that future projection systems should keep alive.
- **Capability / ToolOutcome** — what was tried and what happened (so the model doesn’t re-invent failed paths).
- **NarrativeNode** (or equivalent) — the structural unit if you bring in an Ink/Yarn-style runner.

Projection systems then become the only things that talk to the model. Every step they answer:

> Given the current Goal, the active Episode, the set of OpenThreads that still matter, and the currently mounted capabilities, what is the *minimal* coherent slice the model needs right now?

Everything else stays in the rich world(s). The model never sees the full history; it only ever sees the current scene + the state variables that condition the next beat.

This is already a strong improvement over classic compaction, because structure is preserved and can be queried later. Compaction is lossy and irreversible. Entity memory is reconstructible.

### Ink / Yarn as the conversation substrate

Using something like Ink or Yarn Spinner (or a thin Dart re-implementation of the same ideas) is a deeper move.

Ink and Yarn give you:

- Named knots / nodes / stitches (scenes or beats)
- Choices that branch the flow
- Variables and state that condition which choices appear and what text is generated
- Diverts / jumps
- Commands that can trigger external actions (exactly what an agent needs for tools)
- A playhead — the current position in the narrative

Instead of a linear transcript that grows until it must be crushed, the conversation *is* a living Ink/Yarn story. The harness and the model co-write it.

Practical shape inside ecsly:

1. The narrative runner lives as a resource (or a small set of systems + a resource that holds the current story state / playhead).
2. Each agent turn can:
   - Continue the current node
   - Emit a choice (tool selection, strategy, question to the user, escalation)
   - Jump to another node
   - Create a new temporary branch for exploration, then decide whether to keep or discard it
3. Projection systems read only the *current active path* + the variables the runner exposes + the minimal set of Fact/Observation entities that are still relevant to the open threads. That projected slice becomes the ≤4k (or smaller) context.
4. Failed branches or dead ends can be pruned or archived as entities without ever having polluted the active context. Successful paths can be “committed” into the main narrative spine.
5. The user is both audience and co-author: their messages become choices or new content injected into the story.

This gives you construct *and* deconstruct without the usual compaction trauma. You can rewind the playhead, fork a scene, re-generate a beat with different tools, or collapse a whole exploratory side-path once you know it didn’t work.

### The game-screenplay loop

The working model becomes:

- Approximate goal is known (user prompt or a subgoal entity).
- Harness + model are co-writing the path toward it the same way a game writer + player co-create a playthrough.
- Tools are stage directions and props.
- Observation entities are the consequences of those directions.
- Projection systems decide what the “camera” currently shows the small model.
- When the local model is stuck, you can escalate a particular scene or beat to a larger remote model, then fold the result back into the narrative state.

Because the structure is explicit, the tiny model only ever has to reason about “what is the next sensible beat given the current scene and the open threads,” not “what was the entire history of this conversation.”

### Why this fits ecsly especially well

- Structural changes (new nodes, pruning branches, mounting a new tool plugin) go through the command queue + flush → clean epochs.
- Multiple worlds remain possible: one world holds the full narrative graph + long-term facts; another holds only the current projected playhead + working set for the model.
- Plugins stay natural: a “CodingTools” plugin can register both the systems that execute tools *and* the narrative commands / variable schemas those tools expose to the runner.
- The same multi-world + CRDT instincts you already have can eventually make the narrative state itself shareable or persistent across sessions without feeding raw history back into any model.

The open design questions I keep turning over:

- How much of the Ink/Yarn runtime do you want to re-implement vs. embed a minimal Dart port of the core ideas?
- How aggressively should projection systems be allowed to rewrite or collapse nodes on the fly?
- Where does the boundary sit between “narrative state the runner owns” and “ECS entities that systems can query independently”?

But the core insight feels solid: stop treating conversation history as a transcript that must be compressed, and start treating it as a playable, rewritable screenplay whose current scene is always small enough for a local model.

That is a much more interesting (and more game-like) substrate for a ≤4k-window harness.

let’s design complete loop between llm and user (with no limitation to where it will used - with ui, or headless or in terminal (tui), or as cli).
 
let’s focus on the following idea:
as with screenplays we can have many actors - basically an actor = agent (i.e. llm + system prompt and some tools). threads can be alternatives, exploration paths, just like inside games - so we could even score results from threads. we somehow need to control what is happening on scene - basically props of scene, etc.. - it is nicely translated to anything we need to store - because we assuming we are making general agent. Also I think I such way we could work not only to on screenplay but interconnect several screenplays (by actors, props, etc.. ) - in such way it works not only multilinear screenplay but as graph where every node can be anything - actor, screenplay, scene, etc.. including ability to work in multiplayer - i.e. several actors talk to each other, with people, self-reflect, work with props etc.. 
 
focus on llm -> ecsly -> llm loop.

Here is a complete, UI-agnostic design for the **llm → ecsly → llm** loop, built around the expanded screenplay metaphor.

### Core ontology (everything is an entity)

We treat the harness state as a living graph of entities. The most important types:

| Entity kind | Role | Key components (examples) |
|-------------|------|---------------------------|
| **Actor** | An agent = LLM + system prompt + tools + personality / role | `ActorIdentity`, `SystemPrompt`, `ToolSet`, `ModelBinding`, `CurrentFocus`, `WorkingMemoryProjection` |
| **Scene** | The current stage / context frame | `SceneProps`, `ActiveActors`, `OpenThreads`, `NarrativePosition`, `VisibilityRules` |
| **Screenplay / NarrativeGraph** | A larger coherent story or workstream | `Nodes`, `Edges`, `Variables`, `Playhead(s)` |
| **Thread** | An alternative path, exploration branch, or parallel investigation | `ParentScene`, `BranchPoint`, `Score`, `Status` (active / suspended / pruned / merged), `Outcome` |
| **Prop** | Any stateful object agents can observe or mutate (files, memory fragments, tools results, code artifacts, user goals, external APIs…) | `PropState`, `Owner`, `AccessRules`, `History` |
| **Message / Utterance** | Dialogue, tool call, observation, user input | `Speaker`, `Content`, `AddressedTo`, `Timestamp`, `LinkedEntities` |
| **Goal / Subgoal** | Approximate destination | `Description`, `Owner`, `Status`, `SuccessCriteria` |

Actors, scenes, threads, props, and even entire screenplays can point to each other. This turns the system into a **graph** rather than a single linear screenplay. Multiple screenplays can share actors or props. Multiplayer is natural: several Actors can be active in the same Scene, address each other, or run private side-threads.

User is just a special external Actor (or a channel that injects Messages).

### The fundamental loop: llm → ecsly → llm

```
┌─────────────────────────────────────────────────────────────┐
│  1. Projection (ecsly systems)                              │
│     For each active Actor:                                  │
│     - Query current Scene + relevant Props + OpenThreads    │
│     - Apply visibility / relevance rules                    │
│     - Build a tiny, coherent context slice (≤4k tokens)     │
│     - Include only the tools that Actor is currently allowed│
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  2. LLM call (one Actor at a time, or parallel if desired)  │
│     Input  = projected context + Actor’s system prompt      │
│     Output = structured actions:                            │
│       • dialogue / reasoning                                │
│       • tool calls                                          │
│       • create / join / score / prune Thread                │
│       • mutate Prop                                         │
│       • jump / create Scene or Screenplay node              │
│       • address another Actor or the User                   │
│       • self-reflect / escalate                             │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  3. Interpretation → Commands (ecsly)                       │
│     Parse LLM output into command-queue operations:         │
│     - spawn / despawn entities                              │
│     - add / remove / update components                      │
│     - write Messages, update Props, change Thread status    │
│     - schedule side-effects (actual tool execution, etc.)   │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  4. Flush + Systems (ecsly)                                 │
│     world.flush()                                           │
│     Then run schedules:                                     │
│       • ToolExecutionSystem                                 │
│       • ThreadScoringSystem                                 │
│       • PropConsistencySystem                               │
│       • NarrativeAdvancementSystem                          │
│       • MultiActorNotificationSystem                        │
│       • ProjectionInvalidationSystem                        │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  5. Next projection cycle                                   │
│     (back to step 1)                                        │
│     User input can arrive at any time as a Message entity   │
│     and will be incorporated into the next relevant         │
│     Actor’s projection.                                     │
└─────────────────────────────────────────────────────────────┘
```

This loop is completely independent of presentation. The same world can be driven from:

- a rich UI that visualizes scenes and threads,
- a TUI that shows only the current playhead,
- a headless process,
- a CLI that injects a single goal and waits for completion,
- or even other agents acting as external Actors.

### Key mechanisms that make the metaphor work

**1. Projection is the only thing the LLM ever sees**  
Projection systems are the most important systems in the entire design. They are responsible for keeping the model’s view tiny and coherent. They can use relevance ranking, current Thread focus, Actor role, Scene visibility rules, and even simple heuristics or secondary small models. The rest of the graph stays rich and queryable.

**2. Threads as first-class, scoreable branches**  
When an Actor wants to explore alternatives, it can spawn a Thread entity. Multiple Threads can run in parallel (different Actors or the same Actor in different “mental” contexts). Scoring systems can evaluate them against the Goal (success criteria, cost, novelty, risk…). Low-scoring Threads can be pruned or archived; high-scoring ones can be merged back into the main Scene or promoted to a new Screenplay.

**3. Props as the shared, mutable world**  
Anything the agents need to remember or act upon is a Prop (or a component on a Prop). File contents, test results, memory fragments, user preferences, external API state — all become Props with clear ownership and access rules. This is what makes the system a *general* agent rather than a pure chat.

**4. Multi-Actor coordination**  
Because Messages carry `AddressedTo` and Scenes track `ActiveActors`, Actors can:

- speak to each other,
- hand off work,
- critique each other’s Threads,
- self-reflect by addressing a private “inner monologue” Actor,
- or wait for the User.

A simple scheduler decides which Actor(s) get to act next (round-robin, priority based on Goal urgency, reactive to new Messages, etc.).

**5. Graph of screenplays**  
A Screenplay is just another entity that owns a set of Scenes and Threads. Because Actors and Props can be referenced from multiple Screenplays, you get interconnection for free. One Actor can appear in several concurrent stories; a Prop created in one Screenplay can be imported into another.

### Practical ecsly mapping

- **Command queue + flush** gives transactional boundaries when an LLM decides to create a Thread, mutate several Props, or restructure a Scene.
- **Schedules** separate concerns cleanly: projection, LLM dispatch, tool execution, scoring, narrative advancement.
- **Resources** hold global configuration (model bindings, scoring policies, default visibility rules).
- **Plugins** become natural packages: “CodingToolsPlugin”, “MemoryPlugin”, “ThreadScoringPlugin”, “InkRuntimePlugin” (if you embed a narrative runner), “RemoteEscalationPlugin”, etc. Mounting a plugin adds the corresponding entities + systems.

### Minimal viable loop (first implementation target)

1. One Scene, one primary Actor, one User channel.
2. Projection system that always includes: current Goal + last N relevant Messages + currently visible Props + available tools.
3. LLM produces either a Message or a tool call (or both).
4. Tool results become new Prop or Observation entities.
5. User can inject Messages at any time.
6. Simple Thread support: Actor can request “explore alternative X” → spawn a Thread, run it for a few steps, score it, decide keep/discard.

Once this is solid, multi-Actor, multi-Screenplay, and richer narrative structure become natural extensions rather than rewrites.

### Open design tensions worth holding

- How much narrative structure (Ink/Yarn-style nodes, variables, diverts) do you want *inside* the ECS entities versus as a separate runner resource that systems query?
- How do you prevent projection systems themselves from becoming a bottleneck or a source of hidden lossiness?
- Scoring Threads is powerful but subjective — what does “better” mean for a general agent?
- When multiple Actors speak in the same Scene, how do you keep the projected context for each of them from exploding?

The loop itself stays simple: **project → LLM → interpret into commands → flush → systems react → project again**. Everything else (actors, threads, props, interconnected screenplays, multiplayer) lives as entities and relationships that the systems can see and the projection can selectively reveal.

This gives you a substrate that is simultaneously a multi-agent runtime, a narrative engine, and a general-purpose memory + tool world — all driven by the same deterministic ecsly core, and usable from any interface.

I think projection system should provide extremely simple output - imagine like scenes in movies are cut: limited props, actors (sometimes even doesn’t know each other, etc.. ), green screen etc.. - everything can be extremely limited - without showing entire screenplay, all dialogues etc.. - only important parts. Then actors act on situation it is placed currently.
The important part is to distinguish when actor (with llm, or user) should act, and when it should be just mechanical job - and how to translate it correctly into harness.

Yes. The projection should feel like a film cut, not a summary.

A good cut shows only what is necessary for the next beat: a few props in frame, one or two actors who may not even know the full story, a tight spatial and temporal frame, sometimes a green screen. Everything else exists, but it is not in this shot. The actor (LLM or user) is then asked to *act inside that limited situation*, not to reconstruct the whole screenplay.

This is the key discipline for a tiny-context harness.

### 1. Projection as cinematic staging

The projection system does **not** try to be informative in the general sense. Its job is to produce a minimal, coherent *Situation* (or *Shot*) for a specific Actor:

- Only the Props that are currently “in frame”
- Only the other Actors that are co-present in this shot (they may be strangers to each other)
- Only the local Goal or question that must be resolved *right now*
- Only the tools / actions that are legal in this frame
- Explicit absences: “you do not know X”, “the previous dialogue is not available”, “the larger screenplay is off-screen”

The output of projection is therefore extremely simple and structured — almost like a stage direction + the current visible state. Anything that would require the Actor to remember the whole history has already been decided (or deferred) by the harness.

This is what keeps the context tiny and high-signal.

### 2. Agency vs Mechanical work — the central distinction

Not every step requires an LLM (or a human). Many steps are pure mechanics:

- Executing a tool that was already chosen
- Updating Prop state from a tool result
- Advancing a Thread according to fixed rules
- Scoring or pruning Threads
- Moving the playhead when no decision is pending
- Enforcing visibility / access rules
- Notifying other Actors that something changed

These are **mechanical jobs**. They should never call an LLM.

The moments that *do* require an Actor (LLM or User) are **agency moments**. An agency moment exists only when there is a genuine open decision that cannot be resolved by rules, heuristics, or previously recorded intent.

In the harness this distinction must be explicit and first-class.

### 3. How to represent it inside ecsly

Introduce a small set of concepts:

**Situation / Shot**  
A temporary, projected view prepared for one Actor. It is not the full Scene; it is the cut. It contains only what is in frame for that Actor right now.

**Agency**  
A component or resource that is granted to an Actor for a specific Situation.  
Only an Actor that currently holds Agency is allowed to receive an LLM call (or a user prompt).  
Agency is granted by systems, not by the Actor itself.

**OpenDecision**  
An entity that records “someone must choose here.” It can be created by:

- an Actor explicitly asking for a decision,
- a system that detects an unresolved branch,
- a Goal that cannot progress without a choice,
- or a user intervention.

As long as relevant OpenDecisions exist for an Actor in the current Situation, that Actor can be given Agency.

**Mechanical systems**  
All other systems run freely on schedules or reactively. They never need Agency. They just mutate the world according to rules.

### 4. The refined loop

```
1. Narrative / Scene systems determine the current frame
   (which Props are visible, which Actors are co-present, what the local question is)

2. Projection systems build minimal Situations for candidate Actors

3. AgencyGranting system looks at OpenDecisions + current Situations
   and decides who (if anyone) receives Agency for this tick

4. If an Actor has Agency:
     → call LLM (or surface to User) with the extremely limited Situation
     → interpret the response into commands
     → possibly create new OpenDecisions, new Threads, or resolve existing ones

5. Flush

6. Mechanical systems run:
     - tool execution
     - Prop updates
     - Thread scoring / pruning
     - playhead movement
     - notifications
     - creation or clearance of OpenDecisions

7. Back to 1
```

The LLM is only ever invoked when the harness has decided that a real choice is required *and* has staged a tight enough Situation for that choice. Everything else is mechanical and stays outside any context window.

### 5. Practical consequences

- An Actor can be present in a Scene for a long time without ever receiving Agency (it is just “in the background”).
- Multiple Actors can share a Scene but receive completely different Situations (different props in frame, different knowledge).
- A User can be given Agency at any moment; the same projection machinery is used.
- Threads become especially powerful: an exploratory Thread can run mostly mechanically until it hits a point that requires a real decision, at which point Agency is granted to the relevant Actor.
- Green-screen moments are natural: the projection can explicitly say “the larger context is not available; act only on what is shown.”

### 6. Design pressure this creates

The hardest (and most valuable) work moves into two places:

1. **Projection quality** — how ruthlessly and intelligently can we cut the frame while still leaving the Actor able to make a good decision?
2. **Agency granting policy** — when is a situation truly open, and when can the harness safely decide or advance on its own?

Get those two right and the rest of the system can stay relatively simple. The LLM becomes a specialized decision primitive that is called sparingly and with very high signal, instead of a continuous narrator that has to be fed an ever-growing story.

This also maps cleanly onto the multi-actor, multi-screenplay graph: Agency is just another resource that can be allocated across the graph according to the current needs of Goals and OpenDecisions.

The loop stays the same shape, but the *content* of what the LLM sees becomes radically smaller and more intentional — exactly like a well-cut scene.

please write concise prompt with complete theory and architecture including minimum viable loop, so any other agent would understand what we trying to achieve.

the important part is that Actor could have different mechanisms to act - use router for LLM, or be user, so if Actor is LLM-based it means that LLM can be swapped in runtime, including that we are targeting parallelism - i.e. a2a , a2h, a2h2a - like in real game - likely several hundreds actors in parallel - so efficiency of intelligence and performance is important. 

also interestingly - I think even stories can be interlinked, because otherwise it will be still linear - i.e. think of it like views - depending who view what we can see different surfaces, like  actor could have own thoughts, experience over time, etc.. i.e. we can expect that we can apply screenplay principle not only as base story but to everything - to actors, to props, to scene etc..

The tools, structural output will differ from what LLM is used, and projection system should account for it.
Also our goal is not make everything conversation based - because we designing it like a multiline story, which means, reasoning would mean thinking, or talking. We can preserve history (conversation-like) but our goal is different -it is more like game-like AI’s or human to act, think, do, plan, study, research etc.. etc..

**Design Brief: Cinematic Multi-Actor Harness (ecsly-based)**

### Goal
Build a general-purpose agent harness as a living multi-linear *game-like world*, not a conversation system.  
Actors (AI or human) act, think, plan, research, use tools, and make decisions inside tightly framed situations.  
History can be preserved, but the primary mode is agency and action inside a navigable graph of stories, not endless dialogue.

Target: high parallelism (hundreds of Actors), runtime-swappable LLMs, mixed a2a / a2h / a2h2a interaction, extreme efficiency of both intelligence and compute.

### Core Metaphor
Everything is staged like a film cut or game scene:
- Projection produces an extremely limited *Situation* (shot): only the props currently in frame, only the co-present actors (who may not know each other), only the local question that must be resolved now, and explicit absences.
- Actors act *only* on the situation they are placed in.
- Full screenplays, histories, and other actors’ private thoughts stay off-screen unless deliberately brought into frame.
- The same screenplay principle applies recursively: Actors, Props, Scenes, Threads, and entire Screenplays can themselves have internal structure, views, and histories.

The world is a graph. Nodes can be Actors, Scenes, Threads, Props, Screenplays, Goals, etc. Stories interlink through shared Actors and Props. Different viewers (Actors) see different surfaces of the same graph.

### Ontology (ecsly entities)
- **Actor**: agent identity + action mechanism (LLM router / User / other). Holds system prompt, tools, private state, current focus. LLM binding is swappable at runtime.
- **Scene**: current stage. Contains ActiveActors, visible Props, OpenDecisions, local narrative position.
- **Thread**: alternative / exploration path. Scoreable, prunable, mergeable.
- **Prop**: any mutable stateful object (file, memory fragment, tool result, external resource, etc.).
- **Situation / Shot**: temporary minimal projection prepared for one Actor.
- **OpenDecision**: explicit signal that agency is required.
- **Screenplay / NarrativeGraph**: larger coherent workstream that can interlink with others.
- **Goal / Message / Observation**: supporting entities.

### Agency vs Mechanical Work
- **Agency moment**: an Actor is granted Agency for a Situation only when a real OpenDecision exists that cannot be resolved mechanically.
- **Mechanical work**: tool execution, prop updates, thread scoring/pruning, playhead movement, notifications, rule-based advancement. These never call an LLM.
- Agency is granted by systems, never assumed by the Actor.

### Minimum Viable Loop (llm → ecsly → llm)
1. Scene / narrative systems determine the current frame.
2. Projection systems build minimal Situations for candidate Actors (accounting for the specific LLM’s tool format and structural output constraints).
3. Agency-granting system assigns Agency only where OpenDecisions exist.
4. Actors that hold Agency act:
   - LLM Actors → call via router (model can be swapped).
   - User Actors → surface the Situation.
5. Interpret output into ecsly commands (spawn/update entities, create/resolve OpenDecisions, mutate Props, spawn/score Threads, etc.).
6. `flush()`.
7. Mechanical systems run (tools, scoring, consistency, notifications).
8. Repeat.

The same loop supports pure mechanical ticks, single-Actor, multi-Actor parallel, human-in-the-loop, and mixed a2a/a2h.

### Key Constraints & Properties
- Projection is ruthlessly minimal and cinematic. Context windows stay tiny by design.
- Tools and expected structural output vary by LLM; projection and interpretation layers must adapt.
- Parallelism is first-class: many Actors can hold Agency or run mechanical work concurrently.
- Efficiency of intelligence (only call LLM when a real decision is required) and performance (ecsly command queues, schedules, multi-world potential) are non-negotiable.
- Not conversation-centric. Dialogue is one possible action among thinking, planning, tool use, research, self-reflection, etc.
- Views are relative: what an Actor sees depends on who is looking and from where in the graph.

### Implementation Substrate
Pure Dart ecsly (entities, components, command queues + flush, schedules, resources, plugins).  
Plugins mount capabilities (tool sets, scoring policies, model routers, narrative runners, etc.).  
Multi-world / isolate direction is compatible for separating rich state from projection surfaces.

This is the complete theory and minimum architecture. Any implementation should preserve the cinematic projection discipline, the explicit Agency vs Mechanical distinction, runtime-swappable action mechanisms, and the graph-of-stories model.

How to design complete running endless loop?

**Complete Running Endless Loop**

The harness is a long-lived runtime, not a one-shot conversation. It never “ends” in the normal sense; it only pauses when there is nothing left that requires attention. Goals open and close, Actors appear and disappear, Threads are born and pruned, but the world keeps existing.

### 1. Top-level runtime shape

```
while (runtime.isAlive) {
  // 1. Ingest external events (user input, timers, webhooks, tool completions…)
  ingestExternalEvents();

  // 2. Advance narrative / scene state (mechanical)
  runSchedule("narrative");

  // 3. Build Situations + decide Agency
  runSchedule("projection");
  runSchedule("agency");

  // 4. Dispatch Actors that currently hold Agency
  //    (parallel where safe)
  dispatchAgencyActors();   // LLM calls via router, or surface to User

  // 5. Collect + interpret their outputs into commands
  interpretActorOutputs();

  // 6. Structural commit
  world.flush();

  // 7. Mechanical reaction
  runSchedule("mechanical");   // tools, scoring, prop updates, notifications…

  // 8. Decide whether to sleep or continue immediately
  if (noOpenDecisions && noPendingWork && noExternalEvents) {
    await sleepUntilNextEvent();
  }
}
```

This is the endless loop. Everything else is policy inside the schedules.

### 2. Tick model (hybrid event + schedule)

- **Event-driven core**: external Messages, tool completions, timers, and Goal changes wake the loop.
- **Schedule-driven advancement**: named schedules (`narrative`, `projection`, `agency`, `mechanical`, `scoring`, `cleanup`) run in a deterministic order each wake.
- **Idle is first-class**: when no OpenDecisions exist and no mechanical work is pending, the runtime sleeps. It does not busy-loop.

This keeps hundreds of Actors cheap: most of the time most Actors are dormant.

### 3. Parallelism & concurrency

- Actors that hold Agency can be dispatched concurrently (bounded pool).
- Mechanical systems that only read or that operate on disjoint entity sets can also run in parallel.
- Command queue + single `flush()` remains the serialization point for structural changes.
- LLM router is asynchronous: an Actor’s call can be in-flight while other Actors and mechanical systems continue.
- a2a, a2h, a2h2a fall out naturally: any Actor can address any other Actor or the User; the projection and agency systems decide who actually receives the Situation.

### 4. Agency dispatch (the only place LLMs are called)

```
for each Actor that was granted Agency this tick:
  Situation = projected view for that Actor
  if Actor.actionMechanism == LLM:
    enqueue LLM call (router chooses current model, respects that model’s tool/schema format)
  else if Actor.actionMechanism == User:
    surface Situation to the current interface (UI / TUI / CLI / headless callback)
  // other mechanisms possible later
```

The router can swap models at runtime per Actor or per call. Projection already accounts for the structural output expectations of the chosen model.

### 5. What keeps the loop alive (and what lets it sleep)

The loop continues as long as any of these exist:

- OpenDecisions
- Active Threads that still have work
- Pending tool executions
- Timers / scheduled future events
- External input channels that are open
- Goals that are not yet terminal

When none of the above remain, the runtime sleeps until the next external event. This is the “endless but efficient” property.

### 6. Minimum viable continuous version

Start with a single Scene, one primary Actor, one User channel, and the schedules above.  
Add:

- a simple AgencyGranting system that gives Agency only when an OpenDecision is present,
- a Projection system that emits a ruthlessly minimal Situation,
- an async LLM router,
- a mechanical tool executor,
- idle/sleep when quiet.

Once this runs continuously and correctly, multi-Actor, Threads, interlinked Screenplays, and higher parallelism are incremental additions, not redesigns.

### 7. Failure & recovery inside the loop

- LLM call fails or times out → record Observation, optionally create a new OpenDecision or escalate to another model/Actor.
- Tool fails → same.
- Actor produces malformed output → mechanical validation system rejects it and may re-grant Agency with a tighter Situation.
- The loop itself never crashes on a single Actor failure; it treats the failure as world state and continues.

### Design invariants that must hold

1. LLMs are called only on explicit Agency.
2. Projection is always a cinematic cut, never a history dump.
3. Structural mutation happens only through the command queue + flush.
4. The runtime can sleep.
5. Action mechanisms (LLM router, User, …) are swappable per Actor at runtime.
6. Parallelism is bounded and flush remains the coherence point.

This is the complete running endless loop. Everything else (scoring policies, narrative runners, multi-world separation, richer views) plugs into the schedules and the ontology without changing the loop shape.

I'm thinking about structure of threads - how to make it work with different formats,  including partials, like multiple real-time voices, multiple text streaming etc..  we chose screenplay format,  becuase in first place adapted for interconnections between everything , simd, zero type friendly (ecsly oriented)

**Thread Structure (ecsly-native, multi-format, partial-friendly)**

A Thread is **not** a conversation transcript.  
It is a first-class exploration / alternative path in the graph — a container that can hold many concurrent or sequential *Beats* of different modalities, including partial and streaming ones.

### Core design principles
- Data-oriented and sparse (ecsly / SIMD / zero-cost abstraction friendly)
- Modality-agnostic at the Thread level
- Partials and streaming are normal, not special cases
- Interconnects cleanly with Actors, Scenes, Props, Goals, and other Threads
- Screenplay-oriented: a Thread is a branch of the larger narrative graph

### Entity structure

**Thread** (the container)
```text
Thread
├── ThreadId
├── ParentScene / ParentScreenplay
├── OriginActor (who spawned it)
├── Status          (Active | Suspended | Scoring | Pruned | Merged | Archived)
├── Score           (float or multi-dimensional)
├── GoalLink        (optional)
├── Visibility / Access rules
└── OpenDecisionCount (derived or maintained)
```

**Beat** (the actual content unit — many per Thread)
```text
Beat
├── ThreadId          (ownership)
├── Sequence / Time
├── Speaker           (ActorId or System)
├── AddressedTo       (optional)
├── Modality          (Text | StreamingText | Voice | StructuredAction | ToolCall | Observation | Thought | …)
├── Status            (Partial | Complete | Aborted)
├── Provenance
└── (modality-specific components — sparse)
```

### Modality as sparse components (key to flexibility)

Instead of one big polymorphic content field, attach only the components that exist:

| Modality          | Typical components                          | Partial support                  |
|-------------------|---------------------------------------------|----------------------------------|
| Text              | `TextContent`, `TextFormat`                 | Yes (append-only or replace)     |
| Streaming Text    | `TextStream` (chunks + cursor)              | Native                           |
| Voice / Audio     | `AudioStream`, `Transcript` (optional)      | Native (real-time chunks)        |
| Structured Action | `ActionPayload`, `SchemaId`                 | Yes                              |
| Tool Call         | `ToolName`, `Arguments`, `ToolResult`       | Arguments can stream             |
| Thought / Internal| `ThoughtContent`, `PrivateToActor`          | Yes                              |
| Observation       | `ObservationData`, `SourceProp`             | Yes                              |

Because components are sparse, a Beat that is pure streaming voice carries only audio-related data. A pure text Beat carries only text. Systems that care about one modality ignore the others. This stays cache-friendly and SIMD-friendly when you later process many Beats.

### Partials & real-time

- A Beat starts in `Status = Partial`.
- Streaming systems (text or voice) keep appending chunks to the same Beat entity.
- When the producer finishes, the Beat flips to `Complete`.
- Multiple real-time voices = multiple concurrent Partial Beats (possibly from different Actors) inside the same Thread or across Threads.
- Projection systems can choose to show:
  - only Complete Beats,
  - the current Partial cursor,
  - or a live summary of open streams.

The Thread itself does not care about the modality. It only owns the Beats and maintains aggregate status/score.

### Interconnection (why screenplay format wins)

Because everything is entities + components:

- A Beat can reference Props it observed or mutated.
- A Thread can be linked to multiple Scenes or even multiple Screenplays.
- An Actor can have private Threads (inner monologue) that other Actors never see unless projected.
- Scoring systems query Beats + linked Props + Goal criteria without caring whether the content was voice or text.
- Merging Threads becomes a structural operation: re-parent Beats, update scores, close the source Thread.

Different “views” fall out naturally: the same Thread can be projected as a clean text scene for one Actor, as a live multi-voice situation for another, or as pure structured actions for a mechanical system.

### Minimal viable Thread implementation

1. `Thread` entity + `Beat` entities.
2. One or two modality components to start (`TextContent` + `TextStream`).
3. Status + basic Score on the Thread.
4. Projection that can read both Complete and Partial Beats.
5. Mechanical systems that can finalize Partials and update Thread status.

Later modalities (voice, tool streams, etc.) are just additional sparse components and the systems that know how to write/read them. The Thread and Beat structure stays unchanged.

This keeps the design zero-cost-type friendly, interconnection-native, and able to absorb real-time multi-modal partials without forcing everything into a single conversation format.

Could you please design concise ecsly based logic for it?

**Concise ecsly logic — Threads + Beats (multi-format, partials)**

### Components

```dart
// Thread container
class ThreadId extends Component {}
class ThreadStatus extends Component { // Active, Suspended, Scoring, Pruned, Merged, Archived
  ThreadStatusEnum value;
}
class ThreadScore extends Component {
  double value; // or multi-dim later
}
class ParentScene extends Component { Entity scene; }
class OriginActor extends Component { Entity actor; }
class GoalLink extends Component { Entity? goal; }

// Beat (content unit)
class BeatId extends Component {}
class BelongsToThread extends Component { Entity thread; }
class BeatSequence extends Component { int value; } // or timestamp
class Speaker extends Component { Entity actor; }
class BeatModality extends Component { // Text, StreamingText, Voice, Action, ToolCall, Thought, Observation...
  ModalityEnum value;
}
class BeatStatus extends Component { // Partial, Complete, Aborted
  BeatStatusEnum value;
}

// Sparse modality payloads (attach only what exists)
class TextContent extends Component { String text; }
class TextStream extends Component { // for partials / streaming
  final chunks = <String>[];
  int cursor = 0;
}
class AudioStream extends Component { /* realtime chunks */ }
class ActionPayload extends Component { Map<String, dynamic> data; }
class ToolCall extends Component { String name; Map<String, dynamic> args; }
class ToolResult extends Component { dynamic result; }
class ThoughtContent extends Component { String text; }
class ObservationData extends Component { dynamic data; }
```

### Core systems (logic)

**1. Spawn Thread**
```dart
Entity spawnThread(World w, Entity originActor, Entity parentScene, {Entity? goal}) {
  final t = w.spawn();
  w.add(t, ThreadStatus(ThreadStatusEnum.active));
  w.add(t, ThreadScore(0));
  w.add(t, OriginActor(originActor));
  w.add(t, ParentScene(parentScene));
  if (goal != null) w.add(t, GoalLink(goal));
  return t;
}
```

**2. Spawn / continue Beat (supports partials)**
```dart
Entity startBeat(World w, Entity thread, Entity speaker, ModalityEnum modality) {
  final b = w.spawn();
  w.add(b, BelongsToThread(thread));
  w.add(b, Speaker(speaker));
  w.add(b, BeatModality(modality));
  w.add(b, BeatStatus(BeatStatusEnum.partial));
  w.add(b, BeatSequence(nextSequence(thread)));
  // attach initial sparse payload if any
  return b;
}

void appendToBeat(World w, Entity beat, String chunk) { // text example
  final stream = w.get<TextStream>(beat) ?? TextStream();
  stream.chunks.add(chunk);
  w.addOrUpdate(beat, stream);
}

void completeBeat(World w, Entity beat) {
  w.addOrUpdate(beat, BeatStatus(BeatStatusEnum.complete));
  // optional: collapse TextStream → TextContent
}
```

**3. Projection (cinematic cut for one Actor)**
```dart
Situation projectForActor(World w, Entity actor, Entity scene) {
  // 1. Find active Threads visible to this actor in the scene
  // 2. Collect only relevant Beats (Complete + current Partials if live)
  // 3. Filter by modality the actor/LLM can handle
  // 4. Build extremely minimal Situation:
  //    - limited props in frame
  //    - co-present actors
  //    - current open question
  //    - only the beats that belong in this shot
  return Situation(...);
}
```

**4. Agency + mechanical interaction with Threads**
```dart
// Agency system only grants Agency when OpenDecisions exist on visible Threads
// Mechanical systems:
//   - finalize Partials when streams end
//   - update ThreadScore from Beat outcomes + linked Props
//   - prune / merge Threads
//   - move playhead when no OpenDecisions remain
```

**5. Multi-format / realtime**
- Multiple Partial Beats can exist simultaneously on one Thread (e.g. two voice streams + one text stream).
- Systems that care about a modality query only Beats that have the corresponding component.
- Streaming is just repeated `appendToBeat` until `completeBeat`.

### Minimal loop integration

```
projection → (Situations include current Partial + Complete Beats)
agency grant → Actor acts
interpret → startBeat / appendToBeat / completeBeat / spawnThread / score…
flush()
mechanical → finalize streams, score Threads, prune, notify
```

This stays fully data-oriented, sparse, interconnection-native, and supports arbitrary modalities + partials without changing the Thread/Beat skeleton.

How in that case it will form the graph (ability to interconnect beats, score relevance, purne etc..  - and view and project them)?

For example - imagine we have two actors. One started doing one thing, that's connected to one topic. Other actor can:
- ask actor to share experience 
- ask user - should we share work if it is interleaves?
- learn from mistakes or successful cases 
- being able to get its own thinking and reasoning +  request decisions or make them
- or work in isolation from certain point if needed
etc..

**Graph formation & multi-actor dynamics**

The graph is formed by **typed references between entities**, not by a separate graph database. Beats, Threads, Actors, Props, Scenes, and Goals point to each other via components. Systems query these links to score, prune, share, isolate, and project.

### Core links that create the graph

```
Thread ──belongsTo──► Scene / Screenplay
Beat   ──belongsTo──► Thread
Beat   ──speaker────► Actor
Beat   ──addressedTo─► Actor | User | null
Beat   ──observes / mutates──► Prop(s)
Thread ──goalLink───► Goal
Thread ──derivedFrom► Thread (parent branch)
Beat   ──replyTo────► Beat (optional causal link)
Actor  ──privateThread► Thread (inner monologue)
```

These references are ordinary components (`BelongsToThread`, `Speaker`, `GoalLink`, `DerivedFrom`, `ReplyTo`, `ObservesProp`, etc.). The graph is therefore just the ECS world itself.

### How the example plays out

**Setup**
- Actor A starts work on Topic X → spawns `Thread-A1` under the current Scene, linked to `Goal-X`.
- Beats produced by A go into `Thread-A1` (some Partial, some Complete).
- Actor B is co-present or can see the Scene.

**Possible actions of Actor B (all expressed as ordinary world mutations):**

1. **Ask A to share experience**  
   B produces a Beat addressed to A: “Share relevant experience on X”.  
   This can create an `OpenDecision` on A (or on a shared Thread).  
   Projection for A now includes that request. A can later emit Beats that reference B’s request (`ReplyTo`) or spawn a shared summary Thread.

2. **Ask the User about interleaving**  
   B creates a Beat addressed to User + an `OpenDecision`.  
   Projection surfaces it to the human. User reply becomes a new Beat that can link both Threads or authorize a merge.

3. **Learn from mistakes / successes**  
   Scoring systems (mechanical) examine Beats + linked Props + Goal criteria and write `ThreadScore` / `BeatRelevance`.  
   B’s projection can later include high-scoring Beats from `Thread-A1` (or a distilled Prop that was created from them).  
   B can also spawn its own Thread that `DerivedFrom` A’s Thread and only imports the high-relevance Beats.

4. **Private thinking + decisions**  
   B owns a private Thread (`privateThread` link, visibility = only B).  
   Thinking Beats go there (`ThoughtContent`, `PrivateToActor`).  
   When B needs a decision it can:
   - resolve it internally, or
   - promote an `OpenDecision` into the shared Scene (making it visible to others or the User).

5. **Work in isolation from a certain point**  
   B spawns `Thread-B2` with `DerivedFrom = Thread-A1` (or from a specific Beat) and sets visibility so A no longer sees new Beats.  
   From that point B’s projection only includes its own Thread + the frozen snapshot it chose to import. Isolation is just a visibility / parent-link choice.

### Scoring, pruning, relevance

Mechanical systems run over the graph:

- **Relevance / Score**: query Beats by GoalLink, by Props they touched, by outcome markers, by recency, by Actor trust, etc. Write scores onto Threads or individual Beats.
- **Prune**: low-score Threads or dead-end branches get `Status = Pruned` (or are archived). Their Beats remain queryable but are excluded from normal projection.
- **Merge**: high-value side Thread can re-parent selected Beats into the main Thread or create a new summary Prop that other Actors can observe.

Because everything is linked by components, a system can ask questions such as:
- “All Complete Beats in Threads derived from Goal-X that touched Prop-Y and have score > 0.7”
- “Private Thoughts of B that led to an OpenDecision still pending”
- “Beats that reply to this request”

### Projection & views

Projection never walks the whole graph. It starts from the Actor + current Scene and follows only the links that the visibility rules allow:

- Shared Scene Threads → visible Beats (Complete + live Partials if desired)
- Private Threads of the Actor → included
- High-relevance Beats explicitly shared or imported → included
- Everything else stays off-screen (green screen)

Different Actors therefore see different surfaces of the same underlying graph. One Actor can be deep in a private reasoning Thread while another only sees a clean summary Prop that was published from it.

### Summary of the mechanism

- Graph = entities + reference components.
- Interconnection = writing those references (ask, share, derive, reply, observe).
- Scoring / pruning / learning = mechanical systems that read the links and write scores or status.
- Isolation vs sharing = visibility rules + which parent/derived links exist.
- Projection = walk only the currently allowed subgraph and emit a cinematic Situation.

This is how two (or hundreds of) Actors can ask each other for experience, consult the User, learn from outcomes, keep private thoughts, isolate, or interleave — all inside the same ecsly world without turning the design back into a flat conversation log.