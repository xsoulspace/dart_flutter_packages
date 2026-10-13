# Meaning core dependency and contract qualification — 2026-10-11

Owner: `xsoulspace_meaning_core`, under harness ADR 0089. This lane is separate
from the concurrent convergence-session/mesh work; no files in that lane changed
here. The shared harness connection remains unavailable; no world claim or
canonical acceptance is asserted. Source integration is local and reviewable.

## Dependency audit

| Owner | Current resolution | Reused responsibility |
| --- | --- | --- |
| IntentCall schema | DFP local 1.0.0; harness hosted 0.6.0 | InputSchema, AgentArguments, native validation and exceptions |
| AE wire | local 0.1.0, publish_to none | EditExecutableWire and verification vocabulary, direct reexports |
| Inference core | remains in harness adapter | FM/SchemaBundle and tool definitions, no copied schema algebra |
| DFP live-apply | separate qualified storage package | Recovery implementation; core only describes capabilities |

The new package permits IntentCall `>=0.6.0 <1.1.0`, with explicit tested 0.6/1.0
lanes. Harness lock resolution retains its existing 0.6 stack. No provider,
world, renderer or IO dependency was introduced in the core. AE's private
publication status is retained by `publish_to: none` in the new package.

The [static production library closure](dependency-closure.json) names 54 source
files, exact SHA-256 identities, zero unresolved URIs and these Dart libraries:
collection, convert, math, typed_data. Reachable external packages are AE wire,
IntentCall schema, collection, from_json_to_json and meta. This is a static
library closure, not a claim that declared unused dependencies disappeared or
that every future native consumer is certified.

IntentCall validation supports a subset of JSON Schema. Standard `array` is
portable; the 1.0 `list` alias is not supported by 0.6. Native nested operation
checks remain mandatory. We do not fork its validator or imply full validation.

## Implemented and measured

Portable references, opaque revision kinds, evidence stages, revision-bound view
correspondence, native operation/change/recovery descriptions and JSON handoff
are implemented. Caller-owned maps/lists are captured immutably. Exact mapping
cannot be established by predictions alone. Input arguments validate through
the actual IntentCall API; AE wire fields retain native vocabulary.

Read-program constants, result-projection typedef and envelope/vocabulary
refusals moved from harness into this package. The old harness path reexports
existing names. Executor/cursor, native argument schemas, output cutting, tier
budgets, jailing, consent and world acceptance remain native.

- `just check xsoulspace_meaning_core`: analyzer clean, 5/5 tests on DFP's
  IntentCall 1.0. [Transcript](package-gate.log).
- Isolated copied contract tests against the actual IntentCall 0.6 source:
  5/5 pass. [Transcript](intentcall-06-compatibility.log).
- Independent boundary review confirmed native ownership and found a missing
  baseline evidence stage. `observed` was added and both contract lanes rerun.
  Core contracts are not yet a gesture or source-mapping engine.

Harness full/focused consumer evidence and the frozen next experiment criteria
are in `ecsai_harness/docs/evidence/meaning-core-extraction-2026-10-11/`.
No physical gesture, harness task acceptance, distributed recovery or broad
cross-language meaning preservation follows from these local controls.
