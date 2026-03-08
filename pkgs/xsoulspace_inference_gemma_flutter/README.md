# xsoulspace_inference_gemma_flutter

Flutter Gemma-backed implementation of [xsoulspace_inference_core](https://github.com/your-org/dart_flutter_packages/tree/main/pkgs/xsoulspace_inference_core) for desktop/mobile. Uses [flutter_gemma](https://pub.dev/packages/flutter_gemma) (on-device FunctionGemma).

## Install

Add to your app `pubspec.yaml`:

```yaml
dependencies:
  xsoulspace_inference_gemma_flutter:
    path: ../xsoulspace_inference_gemma_flutter  # or version from pub
  xsoulspace_inference_core:
    path: ../xsoulspace_inference_core
```

Then run `flutter pub get`.

## Update

Bump the dependency version and run `flutter pub get` (or `flutter pub upgrade`).

## Uninstall / rollback

Remove the dependency from `pubspec.yaml`. There is no package-owned system state to clean.

## Version

Version is in `pubspec.yaml`; there is no `--version` CLI (library only).

## Release contract and failure behavior

- **Smoke verification:** From the package root run `make test` (or `flutter test` and, on macOS, `make test-integration` from the example).
- **Failure behavior:** All failures are returned as `InferenceResult.fail` with a `code` and optional `message`/`details`. Codes include:
  - `request_prompt_empty`, `request_working_directory_empty`, `request_schema_empty` — validation (from core).
  - `engine_unavailable` — no active Gemma model or inference error.
  - `codex_output_empty` — model produced no output.
  - `json_parse_failed` — output was not valid JSON.
  - `schema_validation_failed` — output did not match the requested schema.

## Example app and e2e

The `example/` app provides:

- **Check availability** — refreshes and shows whether a Gemma model is active.
- **Install model** — installs from the default Hugging Face URL (network + disk).
- **Run inference** — runs one inference with a simple schema when available.

Run the example: `cd example && flutter run -d macos`. Run integration tests: `cd example && flutter test integration_test -d macos` (skips infer when no model).

## One-command smoke

From the package root:

```bash
make test
```

This runs package unit tests and, on macOS, the example integration test. Full e2e with a downloaded model is optional (manual or CI with model install).
