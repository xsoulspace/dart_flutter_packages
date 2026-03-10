# xsoulspace_inference_whisper_ggml_flutter

Whisper GGML-backed speech-to-text implementation of `xsoulspace_inference_core`.

## Supported task

- `InferenceTask.speechToText`

Unsupported tasks (`structuredText`, `textToSpeech`) return `task_unsupported`.

## Platform matrix (v1)

- Android: supported
- iOS: supported
- macOS: supported
- Linux/Windows/Web: not promised in v1

## Install

```yaml
dependencies:
  xsoulspace_inference_whisper_ggml_flutter:
    path: ../xsoulspace_inference_whisper_ggml_flutter
  xsoulspace_inference_core:
    path: ../xsoulspace_inference_core
```

## Usage

```dart
import 'package:whisper_ggml/whisper_ggml.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_whisper_ggml_flutter/xsoulspace_inference_whisper_ggml_flutter.dart';

final client = WhisperGgmlFlutterInferenceClient(
  initialModel: WhisperModel.base,
);

// Model lifecycle helpers.
final installedModels = await client.getInstalledModels();
if (!installedModels.contains(WhisperModel.base)) {
  await client.downloadModel(WhisperModel.base);
}
await client.selectModel(WhisperModel.base);

final result = await client.infer(
  InferenceRequest.speechToText(
    audioInput: InferenceAudioInput.filePath(
      filePath: '/tmp/input.wav',
      mimeType: 'audio/wav',
    ),
    metadata: {'language': 'en'},
  ),
);

if (!result.success) {
  throw StateError('${result.error?.code}: ${result.error?.message}');
}

final transcript = result.data?.transcript;
final normalized = result.data?.normalizedTranscript;
final segments = result.data?.segments;
```

## Notes

- Input can be file path or in-memory bytes. Byte input is written to a temp file for transcription.
- No microphone ownership and no streaming in v1.
- `normalizedTranscript` strips punctuation and collapses whitespace for grammar-sensitive downstream workflows.

## Testing

```bash
cd pkgs/xsoulspace_inference_whisper_ggml_flutter
flutter test
```

Optional runtime-gated integration smoke:

```bash
cd pkgs/xsoulspace_inference_whisper_ggml_flutter
WHISPER_RUNTIME_INTEGRATION=1 flutter test test/integration/whisper_runtime_integration_test.dart
```
