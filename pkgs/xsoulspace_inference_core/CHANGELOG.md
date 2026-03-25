# Changelog

All notable changes to this package will be documented in this file.

## Unreleased

- Extended `InferenceClient` with lifecycle methods:
  `refreshAvailability()` and `resetAvailabilityCache()`.
- Added request preflight validation via `validateInferenceRequest`.
- Added recursive schema definition validation via `validateSchemaDefinition`.
- Added recursive output schema conformance checks via `validateJsonAgainstSchema`.
- Added tests for nested schema validation and path-aware mismatch reporting.

## 0.1.0-beta.1

- Initial release with provider-agnostic inference contracts.
- Added base JSON parsing and required-key validation helpers.
