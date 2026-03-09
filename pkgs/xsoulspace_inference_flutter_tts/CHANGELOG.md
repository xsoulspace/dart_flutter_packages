## 0.1.0

- Initial `flutter_tts` wrapper implementing `InferenceTask.textToSpeech`.
- Added artifact synthesis response mapping via `InferenceResponse.audioArtifact`.
- Added voice option propagation (`voiceId`, `locale`, `speechRate`, `pitch`).
- Added stable failures for unsupported tasks/platforms and missing audio output artifacts.
