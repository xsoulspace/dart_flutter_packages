# pkgs/xsoulspace_inference_core: Agent Working Agreement

Provider-agnostic inference contracts and validation utilities for text, STT,
and TTS task flows. This package is part of the `dart_flutter_packages`
workspace; Skill Steward is adopted at the workspace root with package-scoped
actions.

## Purpose

Inference backends are unreliable by nature (timeouts, malformed JSON, partial
responses). This package centralizes task contracts, validation, and failure
shapes so all providers expose consistent behavior.

## Agentic harness

The harness product now lives in `~/xs/ecsai_harness` (ADR 0036). This
package stays the provider-agnostic contract: `InferenceClient`,
`Model` / `ModelName` / `ModelId`, `ToolRegistry` / `ToolCall`, and
structured-output schemas. It does not depend on the harness.

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
