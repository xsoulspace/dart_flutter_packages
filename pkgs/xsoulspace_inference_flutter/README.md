# xsoulspace_inference_flutter

Provider-agnostic Flutter helpers for `xsoulspace_inference_core`.

This package accepts injected `InferenceClient`,
`InferenceRealtimeSession<InferenceTranscriptEvent>`, and
`InferenceReadinessProbe` implementations. It does not import any concrete
provider package.

## Usage

```dart
final readiness = await probe.probe();
final notifier = InferenceTranscriptNotifier(session: realtimeSession);

InferenceDiagnosticsPresenter(
  readiness: readiness,
  transcript: notifier.snapshot,
);
```
