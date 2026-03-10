# xsoulspace_inference_web_speech_recognition

Chromium-only Web Speech API (`SpeechRecognition`) implementation of
`xsoulspace_inference_core` for speech-to-text.

## Supported task

- `InferenceTask.speechToText`

Unsupported tasks return `task_unsupported`.

## Platform matrix (v1)

- Chromium-family browsers (Chrome, Edge, Opera, Brave): supported
- Safari / Firefox / non-web runtimes: return `task_unsupported`

## Browser constraints

- Uses Web Speech API constructor from `window.SpeechRecognition` or
  `window.webkitSpeechRecognition`.
- v1 returns one final transcript per `infer(...)` call (no streaming API).
- URL inputs must be browser-loadable (`https:`, `blob:`, `data:`).
- File URL and bytes modes use `<audio>.captureStream()` audio track +
  `recognition.start(audioTrack)`.
- If `start(audioTrack)` is unsupported at runtime, inference fails with
  `task_unsupported` and details reason `audio_track_start_unsupported`.

## Install

```yaml
dependencies:
  xsoulspace_inference_web_speech_recognition:
    path: ../xsoulspace_inference_web_speech_recognition
  xsoulspace_inference_core:
    path: ../xsoulspace_inference_core
```

## Usage

```dart
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_web_speech_recognition/xsoulspace_inference_web_speech_recognition.dart';

final client = WebSpeechRecognitionInferenceClient();

final micResult = await client.infer(
  InferenceRequest.speechToText(
    audioInput: const InferenceAudioInput.microphone(
      mimeType: 'audio/webm',
    ),
    metadata: const <String, dynamic>{'language': 'en-US'},
  ),
);

final urlResult = await client.infer(
  InferenceRequest.speechToText(
    audioInput: const InferenceAudioInput.filePath(
      filePath: 'https://example.com/sample.wav',
      mimeType: 'audio/wav',
    ),
  ),
);

if (!urlResult.success) {
  throw StateError('${urlResult.error?.code}: ${urlResult.error?.message}');
}

final transcript = urlResult.data?.transcript;
final normalized = urlResult.data?.normalizedTranscript;
```

## Error mapping

- Permission/service blocked (`not-allowed`, `service-not-allowed`):
  `task_unsupported`
- Invalid/capture/input issues (`audio-capture`, invalid URL/bytes/track):
  `audio_input_invalid`
- Runtime engine/network/language failures (`network`,
  `language-not-supported`, internal runtime failures): `engine_unavailable`

## Generation

Raw interop files are generated only from the pinned declaration snapshot:

- Source snapshot: `tool/generated/web_speech_recognition.generated.d.ts`
- Generated raw output: `lib/src/raw/web_speech_recognition_raw.g.dart`

Commands:

```bash
cd pkgs/xsoulspace_inference_web_speech_recognition
just generate
just generate-check
```

## Verification

```bash
cd pkgs/xsoulspace_inference_web_speech_recognition
just analyze
just test
just test-web
```
