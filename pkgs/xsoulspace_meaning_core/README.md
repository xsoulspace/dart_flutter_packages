# xsoulspace_meaning_core

Portable meaning references, evidence, revision-bound view correspondence,
native operation/change/recovery descriptions, and existing bounded read-program
specification/validation. It does not execute changes or confer authority.

IntentCall owns `InputSchema` and argument validation. Supported resolution lanes
are the harness's 0.6 and DFP's 1.0; standard JSON Schema `array` works in both,
while the newer `list` alias is not portable to 0.6. Native validation is a subset
of JSON Schema (e.g. nested objects and patterns are not validated); each executor
retains operation-specific checks. AE owns executable and
verification wires. The package references those exact types. It is private
while AE wire is private and local dependency closures remain under audit.

Harness keeps its VM, cursor and tool dispatch, tier budgets, result projection,
permissions and canonical acceptance. Workspace and Codemap keep their native
edit fences and recovery owners. Apply and finalize are distinct host actions.

`MeaningChange.toJson()` emits a candidate description; it is not a persisted
transaction or completion receipt. Evidence references address original prompts,
images, source or traces in the owning store. Native revision kinds cannot be
silently substituted. Source restoration does not prove runtime restoration.

The read constants and refusal helpers are extracted from the harness without
changing wire behavior. JSON input-schema adapters stay with inference owners;
there is no duplicated schema language here.
