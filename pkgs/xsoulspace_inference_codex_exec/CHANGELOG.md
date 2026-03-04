# Changelog

All notable changes to this package will be documented in this file.

## Unreleased

- Added production hardening for `CodexExecInferenceClient`:
  - request prevalidation and working-directory checks;
  - timeout handling with process termination;
  - bounded output size checks;
  - retry controls for timeout/transient/legacy-flag failures;
  - attempt metadata and warnings for observability.
- Added recursive schema validation of inferred output through
  `xsoulspace_inference_core`.
- Added explicit `codex_auth_failed` error mapping for official auth failures
  (for example `401 Unauthorized`).
- Added reliability tests:
  - timeout path;
  - transient retry path;
  - output-size guard;
  - sequential and parallel stability checks.
- Added optional real-binary integration tests gated by
  `CODEX_INFERENCE_INTEGRATION=1` and `CODEX_API_KEY`.

## 0.1.0

- Initial release with Codex CLI-backed inference client.
