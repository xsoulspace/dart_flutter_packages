# xsoulspace_inference_sherpa_onnx_flutter

Sherpa-ONNX streaming and batch speech-to-text wrapper for
`xsoulspace_inference_core`.

## Included API

- `SherpaOnnxInferenceClient`
- `SherpaOnnxRealtimeSttSession`
- `SherpaOnnxModelConfig`
- `SherpaOnnxRuntimeConfig`
- `SherpaOnnxRealtimeConfig`
- `SherpaOnnxStreamingModelPreset`
- `SherpaOnnxAvailabilityProbe`

## Quickstart

```dart
final client = SherpaOnnxInferenceClient(
  modelConfig: const SherpaOnnxModelConfig.streamingZipformerEn20230626(),
  runtimeConfig: const SherpaOnnxRuntimeConfig(
    librarySearchPaths: <String>['/opt/sherpa'],
    modelsDirectory: '/opt/sherpa-models',
  ),
);

final readiness = await SherpaOnnxAvailabilityProbe(
  runtimeConfig: client.runtimeConfig,
  modelPathResolver: client.resolveModelPath,
).probe();
```

Usage flow:
1. Create provider config.
2. Create `SherpaOnnxInferenceClient` or `SherpaOnnxRealtimeSttSession`.
3. Run `SherpaOnnxAvailabilityProbe.probe()`.
4. Bind the injected session/client to generic UI from `xsoulspace_inference_flutter`.
5. Start transcribing.

## Testing

```bash
cd pkgs/xsoulspace_inference_sherpa_onnx_flutter
flutter test
```
