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

This package also hosts a **UI-agnostic, cinematic multi-actor agent harness** built on ecsly. Its North Star is: *a small local model (2–4k context) can be genuinely useful because the harness does the heavy lifting* — the model is a replaceable reasoning primitive, not the source of intelligence.

The working model is a living, multi-linear game world, not a conversation log:

- **Projection** gives each actor a tiny, cinematic *cut* of the world — only what the current decision needs, with explicit green-screen absences. The model never sees full history.
- **Agency** is granted only when a real decision is open; everything else is mechanical. The model is called sparingly.
- **Memory is derived from the storyline.** Threads of beats (text, thought, tool calls, observations) are the source of truth; an actor's memory is a re-derivable view over those threads, compacted into in-thread summaries over time.
- **The loop is continuous and sleeps when idle.** The same world runs headless, in a CLI, or in Flutter.

### Purpose & guardrails

- **Testable without an LLM.** Every part except *write a beat* is deterministic graph logic — scripted mutations should exercise compaction, projection, agency, and escalation with a mock generator.
- **Tiny-context discipline is enforced, not aspirational.** Projection budgets tokens and fails the benchmark if it exceeds them.
- **Parallelism is bounded and safe.** Many actors act concurrently; a single flush remains the coherence point.

See [Agent harness North Star](docs/north_star_agentic_harness.mdx) for the full objective and non-goals.

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
