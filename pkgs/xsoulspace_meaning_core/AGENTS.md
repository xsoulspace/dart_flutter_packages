# Meaning contract ownership

Portable pure Dart descriptions under harness ADR 0089. North Star impact:
applies to DFP's shared-contract ownership. Input schemas and validation belong
to IntentCall; executable wires belong to AE. Reference them, never fork them.

No IO, world, renderer, scheduler, permission authority, executor or journal.
Native adapters own all execution and verification. Revision kinds stay opaque.
Predictions are not observations; candidate correspondence is not exact mapping.

Gate from DFP root: `just check xsoulspace_meaning_core`.
