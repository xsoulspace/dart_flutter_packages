# xsoulspace_inference_apple_foundation

Apple Foundation Models (SystemLanguageModel) implementation of [xsoulspace_inference_core](https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/xsoulspace_inference_core) for macOS 26+. Uses Swift Package Manager exclusively and requires Apple Intelligence for real inference.

## Runtime surfaces

| Surface                 | Transport                         | Host                                 |
| ----------------------- | --------------------------------- | ------------------------------------ |
| Flutter app             | `MethodChannel` (platform plugin) | Flutter engine, macOS 26+            |
| Native CLI / ACP server | `dart:ffi` C-ABI bridge           | Pure Dart process, no Flutter engine |

Both surfaces share the same Swift core (`FoundationModelsBridge`,
`DartSchemaMaterializer`). The FFI surface is in progress; see
[AGENTS.md](AGENTS.md) for status and guardrails.

## Installation

In your Flutter app:

```yaml
dependencies:
  xsoulspace_inference_apple_foundation:
    path: ../path/to/xsoulspace_inference_apple_foundation # or published version
```

Then `flutter pub get`.

## Usage

```dart
import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

final client = AppleFoundationInferenceClient();
await AppleFoundationInferenceClient.refreshAvailability();
if (client.isAvailable) {
  final result = await client.infer(const InferenceRequest(
    prompt: 'Your prompt',
    outputSchema: {'type': 'object', 'properties': {'answer': {'type': 'string'}}},
    workingDirectory: '/tmp',
  ));
}
```

## Task support

- Supported: `InferenceTask.structuredText`
- Unsupported: `InferenceTask.speechToText`, `InferenceTask.textToSpeech`
  return `task_unsupported`.

## Smoke verification

- **Unit tests** (no native engine, runs on any platform):
  ```bash
  flutter test
  ```
- **E2E / integration test** (real plugin on macOS; skips infer if engine unavailable):
  ```bash
  cd example && flutter test integration_test -d macos
  ```
  Full e2e requires macOS 26+ with Apple Intelligence.

One-command smoke from package root:

```bash
just test
```

## Example app

Run the example on macOS:

```bash
cd example && flutter run -d macos
```

The example shows "Check availability" and "Run inference" with a fixed schema.
