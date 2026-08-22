# Changelog

All notable changes to this package will be documented in this file.

## 0.1.0-beta.1

- `GemmaFlutterInferenceClient` implements `InferenceClient` and
  `ProvisionableInferenceClient` from `xsoulspace_inference_core`.
- Supported tasks: `InferenceTask.text` (raw completion) and
  `InferenceTask.implicitlyStructuredText` (prompt-engineered JSON with schema
  validation and one automatic repair attempt on validation failure).
- `GemmaModelSetup.ensureReady(purpose, constraints)` — purpose-driven
  provisioning from a curated catalog (`GemmaModelCatalog`): consent,
  network-policy, and size-cap checks, broadcast progress stream, cancel
  token, idempotent re-entry.
- `GemmaFlutterInferenceClient.ensureReady` — same contract, plus model load
  into the engine on success.
- Explicit installs remain available: `installFromUrl`, `installFromFile`,
  `cancel`, `getStatus`.
- Honors `systemPrompt` and `contextFragments` from `InferenceRequest`.
- Failure codes standardized: `output_empty` (was `codex_output_empty`),
  `user_consent_required`, `network_not_allowed`, `model_too_large`,
  `model_not_found`, `provision_failed`, `model_install_failed`.
