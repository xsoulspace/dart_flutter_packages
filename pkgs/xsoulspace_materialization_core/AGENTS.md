# Materialization core

Pure Dart compiler and binding-data ownership under harness ADR 0091.
North Star impact: applies to DFP reusable tooling ownership.

No IO, ECS world, model transport, consent authority, executor or journal.
Observed expressions are host-resolved inputs, not authorization evidence.
Unsupported shapes remain named failures. The native adapter owns source
revision, observation authorization, verification and mutation.

Gate from DFP root: `just check xsoulspace_materialization_core`.


`TextChangeCandidate` is immutable candidate data, not authority. Keep exact
absence/text, observed-change requirements and bounded canonical version-1 JSON.
Constructor/fromJson budgets are host supplied; `decode` accepts only canonical
saved bytes. Native workspace identity resolution, fresh adoption policy,
verification and the single recovery journal remain outside this package.
