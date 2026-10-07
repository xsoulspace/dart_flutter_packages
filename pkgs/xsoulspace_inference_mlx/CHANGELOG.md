# Changelog

## 0.1.0

- Initial version: local small text-model composition — `MlxServeRuntime`
  (health-gated loopback serve over the shared local-serve core,
  `mlx_lm.server` defaults), `MlxLocalTextClient` (`InferenceClient` over an
  OpenAI-compatible chat wire), `FakeMlxChatServer` + `ScriptedMlxChatEngine`
  (pure-Dart wire fake), nap-drafting prompt contracts with a refusal law,
  and provenance-stamped `NapDraftRecord`s in a review-only sidecar queue.
