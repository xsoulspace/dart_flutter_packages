# xsoulspace_inference_vosk_flutter

Vosk small-model wrapper for `xsoulspace_inference_core`, focused on
low-footprint local realtime speech-to-text.

## Included API

- `VoskInferenceClient`
- `VoskRealtimeSttSession`
- `VoskAvailabilityProbe`
- `VoskModelConfig`
- `VoskRuntimeConfig`
- `VoskRealtimeConfig`
- `VoskModelPreset`

## Quickstart

1. Create provider config.
2. Create `VoskInferenceClient` or `VoskRealtimeSttSession`.
3. Run `VoskAvailabilityProbe.probe()`.
4. Bind the injected session/client to generic UI from `xsoulspace_inference_flutter`.
5. Start transcribing.

```dart
final client = VoskInferenceClient(
  modelConfig: const VoskModelConfig(),
  runtimeConfig: const VoskRuntimeConfig(
    librarySearchPaths: <String>['/opt/vosk'],
    modelDirectory: '/opt/models',
  ),
);

final readiness = await VoskAvailabilityProbe(
  runtimeConfig: client.runtimeConfig,
  modelPathResolver: client.resolveModelPath,
).probe();
```

## Testing

```bash
cd pkgs/xsoulspace_inference_vosk_flutter
flutter test
```
