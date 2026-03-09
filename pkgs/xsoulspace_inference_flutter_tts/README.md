# xsoulspace_inference_flutter_tts

`flutter_tts`-backed text-to-speech implementation of `xsoulspace_inference_core`.

## Supported task

- `InferenceTask.textToSpeech`

Unsupported tasks (`structuredText`, `speechToText`) return `task_unsupported`.

## Platform matrix (v1)

- Android: artifact synthesis supported
- iOS: artifact synthesis supported
- macOS: returns `task_unsupported` for artifact-only TTS in v1
- Linux/Windows/Web: not supported for this wrapper in v1

## Install

```yaml
dependencies:
  xsoulspace_inference_flutter_tts:
    path: ../xsoulspace_inference_flutter_tts
  xsoulspace_inference_core:
    path: ../xsoulspace_inference_core
```

## Usage

```dart
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_flutter_tts/xsoulspace_inference_flutter_tts.dart';

final client = FlutterTtsInferenceClient();

final result = await client.infer(
  InferenceRequest.textToSpeech(
    text: 'Thanks for your message. Here is a corrected version.',
    workingDirectory: '/tmp',
    metadata: {
      'output_file_path': '/tmp/reply.wav',
      'output_mime_type': 'audio/wav',
    },
    voiceOptions: const InferenceVoiceOptions(
      locale: 'en-US',
      speechRate: 0.9,
      pitch: 1.0,
    ),
  ),
);

if (!result.success) {
  throw StateError('${result.error?.code}: ${result.error?.message}');
}

final artifact = result.data?.audioArtifact;
```

## Notes

- Wrapper is artifact-only in v1: no playback side effects and no streaming.
- Set `metadata['output_file_path']` to control where synthesized audio is written.
- If no output path is provided, the wrapper creates `tts_<timestamp>.wav`/`.caf` in `workingDirectory`.

## Testing

```bash
cd pkgs/xsoulspace_inference_flutter_tts
flutter test
```

Optional runtime-gated integration smoke:

```bash
cd pkgs/xsoulspace_inference_flutter_tts
FLUTTER_TTS_RUNTIME_INTEGRATION=1 flutter test test/integration/flutter_tts_runtime_integration_test.dart
```
