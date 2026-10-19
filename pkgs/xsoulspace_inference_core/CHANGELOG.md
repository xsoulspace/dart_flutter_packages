## Unreleased

- Add opt-in declarative session/cache composition and provider affinity; retain ordinary request defaults.

- Add optional safe transport fingerprints and provider-assisted cache comparison
  request metadata; adapter-declared diagnostic-only paths can be excluded from
  compatibility without removing exact-wire evidence.

- Share content-free HTTP rejection phrase hints across adapters; retain only
  fixed categories and parameter names when code/param yield no safe reason.

- Add provider-neutral offline context fingerprints, cumulative boundary evidence,
  separate cache write/lookup declarations and comparison/matrix utilities.
  Optional transport diagnostics default to no source; encrypted and missing
  legacy evidence preserve incomplete or unknown coverage.

- Preserve original provider output separately from nullable presentation text;
  explicit empty presentation carries no visible discussion.

- Add explicit reasoning effort to composable generation/request codecs and an
  optional provider capability; add caller-owned tool streaming without changing
  the existing text-stream interface.

- Expose `decodeJsonWithUniqueKeys` for embedded tool payloads, reusing the
  syntax parser guard to reject nested and escaped duplicate keys.

- Validate JSON-Schema `anyOf`, additional properties and array bounds. Required
  keys now mean presence, permitting explicitly declared nullable values. Reject
  malformed or explicit-null definitions for these supported constructs.

- Preserve optional native tool call IDs/namespaces and correlated execution
  results through `InferenceResponse` serialization. Legacy calls remain valid.

- Add declarative bounded tool-call syntax composition, explicit profiles, source spans and atomic named refusals.
- Version the Qwen profile to v2 with explicit orphan-closing-marker refusals;
  custom envelopes can opt into the same reserved-marker diagnostic.

# Changelog

All notable changes to this package will be documented in this file.

## Unreleased

- Added provisioning contract: `ProvisionableInferenceClient`,
  `ProvisionConstraints`, `ProvisionProgress`, `ProvisionPhase`,
  `ModelPurpose`, `ModelHandle` (`src/inference_provisioning.dart`).
  Local providers adopt it optionally; cloud providers are unaffected.
- Extended `InferenceClient` with lifecycle methods:
  `refreshAvailability()` and `resetAvailabilityCache()`.
- Added request preflight validation via `validateInferenceRequest`.
- Added recursive schema definition validation via `validateSchemaDefinition`.
- Added recursive output schema conformance checks via `validateJsonAgainstSchema`.
- Added tests for nested schema validation and path-aware mismatch reporting.

## 0.1.0-beta.1

- Initial release with provider-agnostic inference contracts.
- Added base JSON parsing and required-key validation helpers.
