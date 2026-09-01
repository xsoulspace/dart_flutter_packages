---
name: dart-flutter-packages
description: Use when working in the dart_flutter_packages monorepo — editing packages under pkgs/ (especially xsoulspace_agentic_harness (agent harness) and xsoulspace_inference_core (inference contracts), or inference providers like xsoulspace_inference_gemma_flutter / xsoulspace_inference_apple_foundation), running validation, or onboarding to the repo.
---

# dart_flutter_packages Working Guide

## Validation (scoped, never full-workspace)

```bash
just check [package]        # analyze + test for one package
just analyze-one <package>  # analyze only
just test-one <package>     # test only
just demo                   # run headless golden examples of the agent harness
```

Prefer the pi tools `workspace_check`, `test_baseline_record`, `test_baseline_check`
(see `.pi/extensions/dart-workspace.ts`) over raw `flutter test` — they scope output
and separate pre-existing failures from regressions.

**Known-failing tests exist.** Before editing a package with red tests, record a
baseline (`test_baseline_record`); before claiming done, use `test_baseline_check`.

## Agent harness fast path (xsoulspace_agentic_harness)

The harness is an ECS-based multi-actor agent loop. Read in this order:

1. `pkgs/xsoulspace_agentic_harness/docs/agent/architecture.mdx` — one diagram +
   invariants (schedules → systems → events → resources).
2. Runnable golden examples, pure Dart, run with `dart run` from `example/`:
   - `example/lib/headless/01_minimal_loop.dart` — bootstrap + run-until-idle
   - `02_tool_routing.dart` — tool registration & world-routed execution
   - `03_scripted_faults.dart` — deterministic testing via ScriptedGenerationHandler
   - `04_real_model_openrouter.dart` — real provider wiring
3. Recipes are embedded as dartdoc on `HarnessLoop`, `AgentWorldSetup`,
   `ScriptedGenerationHandler`.

### Invariants worth defending

- The generation handler **never executes tools**; the world's
  `toolExecutionSystem` does. Native (Apple FM) and tag-parsed calls share one path.
- Memory is **projection over beat-threads**, never a log; summaries are deliberate
  transforms.
- Projection is token-budgeted; benchmarks fail if exceeded.
- End every harness test with `expectIdle(world)` (test/support).
- **Every loop is monotonic-budgeted (J1.5)**: never reset `ToolRoundCount`/
  `RetryCount`/`AttemptCount` inside a policy — use `openFreshDecision` for
  host-injected fresh decisions; `RetryCount` must survive tool-call
  continuations (a flaky backend looped 255× on-device before this rule).
- Adding an inference provider = register an `InferenceClient` builder in
  `ModelRouter.inferenceClientsBuilders` + a `Model` entry. Nothing else changes.
  Do NOT modify core's public API from provider packages.

### Footguns

- **Dart string interpolation: bare `$id.member` interpolates ONLY the id** —
  `'$jail.path/file'` yields `<jail>/.path/file` (`.path/...` treated as a
  literal suffix). Always write `'${jail.path}/file'`. This silently wrote
  materialized files outside the jail and cost a debug cycle.
- **Nested raw-string templates**: when a generated file embeds a JSON ops
  table inside a template, the inner delimiter must be `r"""..."""` (raw
  triple-double-quote) — non-raw `"""` consumes `\"` escapes (breaks JSON at
  runtime), and `r'''` collides with an outer `r'''` template (syntax errors).
- **Move acks must zoom to `point`**: AFM's native session accumulates every
  tool result, so a full/local view cut per move floods a 4k context within
  ~28 moves (12k tokens). `meaningCut(zoom: 'point')` keeps feedback O(1).
- **Component registration ORDER matters (J1.5 debug cycle)**: new Component
  classes go at the very END of both `data_models/components.dart` AND the
  `AgentPlugin.install` chain — ecsly assigns ids in registration order;
  mid-chain inserts shift host-registered ids → "Bad state: Column should
  exist after archetype creation". ADR-0009 plan-frontier components live
  in `data_models/components.dart` (re-exported by `world_builder.dart`).
- **ReAct continuation ends on text-only responses**: a scripted handler that
  interleaves prose fills (no tool calls) with moves stops the chain at the
  first prose turn. Pair non-terminal prose with a cheap tool call, or emit
  all moves in one response.
- **Every Component class MUST be registered in `AgentPlugin.install`**
  (`registerObjectComponent`). An unregistered object component co-spawning
  with registered ones corrupts ecsly archetype column allocation — tests
  fail with "Bad state: Column should exist after archetype creation".
  New components: add to the plugin chain; ADR-0009 plan-frontier components
  live in `data_models/components.dart` (re-exported by `world_builder.dart`).
- `fs_tools.dart` uses `dart:io` and is intentionally NOT exported from the core
  barrel — importing it into web-targeting code breaks compilation late.
- Fire-and-forget actor concurrency means races; one flush is the coherence point.
  See `run_until_idle_tool_race_test.dart` before adding systems.

## Repo conventions

- Skill Steward: `steward map` shows the operational desk; validate via
  `steward action <pkg>.analyze|.test`.
- Each package has its own AGENTS.md working agreement — read it before editing.
- Classify `north_star_impact` before durable structural changes (see root AGENTS.md).
