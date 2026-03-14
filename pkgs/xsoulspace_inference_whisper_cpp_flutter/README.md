# xsoulspace_inference_whisper_cpp_flutter

`whisper.cpp` wrapper for `xsoulspace_inference_core`, covering batch
transcription plus low-latency incremental transcription sessions around
`whisper-stream`.

## Included API

- `WhisperCppInferenceClient`
- `WhisperCppRealtimeSttSession`
- `WhisperCppModelPreset`
- `WhisperCppModelConfig`
- `WhisperCppRuntimeConfig`
- `WhisperCppRealtimeConfig`
- `WhisperCppAvailabilityProbe`

## Quickstart

```dart
final client = WhisperCppInferenceClient(
  modelConfig: const WhisperCppModelConfig(),
  runtimeConfig: const WhisperCppRuntimeConfig(
    librarySearchPaths: <String>['/opt/whisper'],
    modelsDirectory: '/opt/whisper-models',
  ),
);

final readiness = await WhisperCppAvailabilityProbe(
  runtimeConfig: client.runtimeConfig,
  modelPathResolver: client.resolveModelPath,
).probe();
```

Usage flow:
1. Create provider config.
2. Create `WhisperCppInferenceClient` or `WhisperCppRealtimeSttSession`.
3. Run `WhisperCppAvailabilityProbe.probe()`.
4. Bind the injected session/client to generic UI from `xsoulspace_inference_flutter`.
5. Start transcribing.

## Testing

```bash
cd pkgs/xsoulspace_inference_whisper_cpp_flutter
flutter test
```
