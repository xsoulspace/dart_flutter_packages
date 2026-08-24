/// ACP-backed implementation of xsoulspace_inference_core.
///
/// Exposes [AcpInferenceClient], which drives any Agent Client Protocol (ACP)
/// agent subprocess (`claude-code-acp`, `gemini`, a custom Dart agent built
/// on `dart_acp_toolkit`, …) through the standard `InferenceClient` /
/// `StructuredTextStreamingInferenceClient` interfaces — so apps can treat
/// "an external coding agent" as just another pluggable inference backend.
library;

export 'src/acp_inference_client.dart';
