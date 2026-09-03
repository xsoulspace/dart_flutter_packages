# pkgs/xsoulspace_agentic_dart_meaning: Agent Working Agreement

Dart domain host for the agentic harness (ADR 0015/0022): the workspace
oracle becomes the intent oracle. The model never writes code tokens; the
host derives, materializes, and verifies.

## Modules

| Path | Role |
| --- | --- |
| `lib/src/test_etl.dart` | ETL-in: failing suite → intent skeletons + DERIVED expectations (declared signatures, or greenfield inference from suite imports/literals). Zero host-authored expectations. |
| `lib/src/dart_materializer.dart` | ETL-out: meaning chains → idiomatic workspace Dart (expression-stack → structured if/else). Unsupported shapes fail as NAMED problems. |
| `lib/src/workspace_meaning_runner.dart` | The runner: derive → model fills bounded slots → derived-expectation replay in-loop → HOST materializes → workspace convention (`dart test`) grades. |
| `test/workspace_oracle_e2e_test.dart` | THE R6 gate (ADR 0022 validation). |
| `tool/r6_probe.dart` | Evidence re-run probe (`dart run tool/r6_probe.dart`). |

## Invariants

- Expectations are DERIVED from the workspace suite, never authored
  (ADR 0022 §1). A host-authored table here is a conformance violation.
- The model surface is `intent_define` + `intent_call` (+ act_with_project
  repair). The model NEVER writes code tokens, never sees an AST.
- Materialization is host-side, before every gate, zero model tokens.
- Unsupported compiler shapes fail as named problems — never silently,
  never by generating wrong code.
- Vocabulary growth happens in the CORE via data + verification
  (`meaningExecutorOps`), never by editing this host.

## Validation

```bash
cd pkgs/xsoulspace_agentic_dart_meaning
flutter pub get && dart analyze && flutter test   # or dart test
```

The e2e gate spawns real `dart pub get`/`dart test` subprocesses in a temp
jail (needs network on first run).

## Plan

[ADR 0022](../../docs/decisions/0022_workspace_oracle_meaning_pipeline.md) ·
[R6 in PLAN.md](../xsoulspace_agentic_harness/docs/agent/PLAN.md) ·
[results_r6.md](../xsoulspace_agentic_harness/docs/agent/results_r6.md)
