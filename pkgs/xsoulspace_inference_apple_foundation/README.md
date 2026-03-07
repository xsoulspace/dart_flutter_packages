# xsoulspace_inference_apple_foundation

Apple Foundation Models (SystemLanguageModel) implementation of [xsoulspace_inference_core](https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/xsoulspace_inference_core) for macOS. Requires macOS 26+ and Apple Intelligence for real inference.

## Installation

In your Flutter app:

```yaml
dependencies:
  xsoulspace_inference_apple_foundation:
    path: ../path/to/xsoulspace_inference_apple_foundation  # or published version
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

## Smoke verification

- **Unit tests** (no native engine, runs on any platform):
  ```bash
  flutter test
  ```
- **E2E / integration test** (real plugin on macOS; skips infer if engine unavailable):
  ```bash
  cd example && flutter test integration_test -d macos
  ```
  Full e2e requires macOS 26+ with Apple Intelligence; on older macOS or without Apple Intelligence the test still passes (availability check only).

One-command smoke from package root:

```bash
make test
```

## Example app

Run the example on macOS:

```bash
cd example && flutter run -d macos
```

The example shows "Check availability" and "Run inference" with a fixed schema.
