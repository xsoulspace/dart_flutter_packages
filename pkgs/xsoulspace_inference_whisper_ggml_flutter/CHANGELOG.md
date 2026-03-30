## 0.1.0-beta.1

- Initial STT wrapper for `whisper_ggml` integrated with `InferenceClient`.
- Added model lifecycle helpers (`getInstalledModels`, `downloadModel`, `selectModel`, `deleteModel`).
- Added `InferenceRequest.speechToText` support including bytes-to-temp-file materialization.
- Added mapping to `InferenceResponse.transcript`, `normalizedTranscript`, and timestamped `segments`.
