# Changelog

All notable changes to this package will be documented in this file.

## 0.1.0-beta.1

- `GemmaFlutterInferenceClient` implements `InferenceClient` and
  `ProvisionableInferenceClient` from `xsoulspace_inference_core`.
- Supported tasks: `InferenceTask.text` (raw completion) and
  `InferenceTask.implicitlyStructuredText` (prompt-engineered JSON with schema
  validation and one automatic repair attempt on validation failure).
- `GemmaModelSetup.ensureReady(purpose, constraints, platform)` — purpose-
  driven provisioning from a curated platform-aware catalog
  (`GemmaModelCatalog`): consent, network-policy, and size-cap checks,
  broadcast progress stream, cancel token, idempotent re-entry. Validated
  targets: Android and macOS.
- Catalog: Gemma 4 E2B/E4B (Android/iOS/macOS) and Gemma 4 12B (macOS coding
  tier). All URLs verified against the HuggingFace API; CodeGemma 7B was
  evaluated and rejected (512-token KV cache is below the harness projection
  budget).
- `GemmaFlutterInferenceClient.ensureReady` — same contract, plus model load
  into the engine on success.
- Explicit installs remain available: `installFromUrl`, `installFromFile`,
  `cancel`, `getStatus`.
- Honors `systemPrompt` and `contextFragments` from `InferenceRequest`.
- Failure codes standardized: `output_empty` (was `codex_output_empty`),
  `user_consent_required`, `network_not_allowed`, `model_too_large`,
  `model_not_found`, `provision_failed`, `model_install_failed`.
