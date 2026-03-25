# xsoulspace_inference_elevenlabs_flutter

ElevenLabs API-backed speech inference package for
`xsoulspace_inference_core`, with:

- `InferenceTask.textToSpeech` via `ElevenLabsTtsInferenceClient`
- `InferenceTask.speechToText` via `ElevenLabsSttInferenceClient`
- Realtime websocket sessions for TTS and STT

Unsupported tasks return `task_unsupported`.

## Install

```yaml
dependencies:
  xsoulspace_inference_elevenlabs_flutter:
    path: ../xsoulspace_inference_elevenlabs_flutter
  xsoulspace_inference_core:
    path: ../xsoulspace_inference_core
```

## Auth and Endpoint Config

```dart
const auth = ElevenLabsAuthConfig(apiKey: 'YOUR_ELEVENLABS_API_KEY');
const endpoint = ElevenLabsEndpointConfig(
  baseHttp: Uri.parse('https://api.elevenlabs.io'),
  timeout: Duration(seconds: 30),
);
```

HTTP `infer(...)` requires `apiKey`.
Realtime sessions use `bearerTokenProvider` when available, otherwise `apiKey`.

## TTS Usage

```dart
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_elevenlabs_flutter/xsoulspace_inference_elevenlabs_flutter.dart';

final ttsClient = ElevenLabsTtsInferenceClient(
  authConfig: const ElevenLabsAuthConfig(apiKey: 'YOUR_KEY'),
);

final result = await ttsClient.infer(
  InferenceRequest.textToSpeech(
    text: 'Hello from ElevenLabs.',
    workingDirectory: '/tmp',
    metadata: const <String, dynamic>{
      'output_file_path': '/tmp/hello.mp3',
    },
    voiceOptions: const InferenceVoiceOptions(
      voiceId: 'VOICE_ID',
      providerExtras: <String, dynamic>{
        'model_id': 'eleven_multilingual_v2',
        'output_format': 'mp3_44100_128',
        'stability': 0.5,
        'similarity_boost': 0.8,
      },
    ),
  ),
);

if (!result.success) {
  throw StateError('${result.error?.code}: ${result.error?.message}');
}

final artifact = result.data?.audioArtifact;
```

TTS provider extras currently supported:
`model_id`, `stability`, `similarity_boost`, `style`,
`use_speaker_boost`, `speed`, `seed`, `output_format`, `language_code`,
`enable_logging`, `optimize_streaming_latency`,
`apply_text_normalization`, `apply_language_text_normalization`.

## STT Usage

```dart
final sttClient = ElevenLabsSttInferenceClient(
  authConfig: const ElevenLabsAuthConfig(apiKey: 'YOUR_KEY'),
);

final result = await sttClient.infer(
  InferenceRequest.speechToText(
    audioInput: const InferenceAudioInput.filePath(
      filePath: '/tmp/input.wav',
      mimeType: 'audio/wav',
    ),
    metadata: const <String, dynamic>{
      'model_id': 'scribe_v1',
      'language_code': 'eng',
      'diarize': true,
      'tag_audio_events': false,
      'timestamps_granularity': 'word',
    },
  ),
);

if (!result.success) {
  throw StateError('${result.error?.code}: ${result.error?.message}');
}

print(result.data?.transcript);
```

STT supports `audioInput.filePath` and `audioInput.bytes`.
`audioInput.microphone` returns `task_unsupported`
with reason `microphone_requires_realtime_session`.

## Realtime TTS

```dart
final session = ElevenLabsRealtimeTtsSession(
  authConfig: ElevenLabsAuthConfig(
    bearerTokenProvider: () async => 'YOUR_BEARER_TOKEN',
    apiKey: 'YOUR_API_KEY_FALLBACK',
  ),
);

await session.connect(voiceId: 'VOICE_ID', modelId: 'eleven_multilingual_v2');
await session.initialize();

session.events.listen((event) {
  if (event.audioBytes != null) {
    // Handle decoded audio chunk bytes.
  }
});

await session.sendText(text: 'Hello realtime! ', tryTriggerGeneration: true);
await session.flush();
await session.closeInput();
await session.close();
```

## Realtime STT

```dart
final session = ElevenLabsRealtimeSttSession(
  authConfig: const ElevenLabsAuthConfig(apiKey: 'YOUR_KEY'),
);

await session.connect(
  modelId: 'scribe_v1',
  audioFormat: 'pcm_16000',
  sampleRate: 16000,
  commitStrategy: 'manual',
);

session.events.listen((event) {
  if (event.messageType == 'partial_transcript') {
    print(event.transcript);
  }
});

await session.sendAudioChunk(audioBytesChunk);
await session.commit();
await session.close();
```

## Error Mapping

- 400/422 -> `request_invalid`
- 401/403 -> `auth_failed`
- 404 -> `resource_not_found`
- 408/429/5xx/network timeout -> `engine_unavailable`
- Unsupported task/source/runtime -> `task_unsupported`

## Testing

```bash
cd pkgs/xsoulspace_inference_elevenlabs_flutter
flutter test
```

Optional runtime integrations:

```bash
cd pkgs/xsoulspace_inference_elevenlabs_flutter
ELEVENLABS_RUNTIME_INTEGRATION=1 \
ELEVENLABS_API_KEY=... \
ELEVENLABS_TEST_VOICE_ID=... \
flutter test test/integration/elevenlabs_tts_runtime_integration_test.dart

ELEVENLABS_RUNTIME_INTEGRATION=1 \
ELEVENLABS_API_KEY=... \
ELEVENLABS_STT_AUDIO_PATH=/absolute/path/to/sample.wav \
flutter test test/integration/elevenlabs_stt_runtime_integration_test.dart
```
