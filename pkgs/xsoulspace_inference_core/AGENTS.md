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

The agent harness moved to `pkgs/xsoulspace_agentic_harness`
(ADR 0012). Contracts it consumes that live here: `InferenceClient`,
`Model`/`ModelName`/`ModelId`, `ToolRegistry`/`ToolCall`,
structured-output schemas. See
[../xsoulspace_agentic_harness/AGENTS.md](../xsoulspace_agentic_harness/AGENTS.md).

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
