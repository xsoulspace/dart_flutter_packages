# pkgs/xsoulspace_agentic_workspace: Agent Working Agreement

Workspace domain host for the agentic harness (ADR 0026 — renamed from
`xsoulspace_agentic_dart_meaning`; the machinery was already generic: zero
analyzer imports, `fs_etl` indexes every file class, `span_editor` is a
generic splice engine). The workspace oracle becomes the intent oracle;
language support is a **SPEC FAMILY as data** — Dart today (`code_etl`,
`test_etl`, `dart_materializer`), md/yaml/json/text families land BESIDE
the registry per ADR 0024, never as a fork.

**Law (ADR 0026 §1): a new problem class lands as a materializer spec —
never a new loop, a new tool, or a raw read/write path.**

## Adding a file class (the extensibility answer — ADR 0024 §2 as data)

The read side is registry-driven (`lib/src/file_class_spec.dart`): a file
class = one `FileClassSpec` entry (extensions + optional mechanical
extractor). To extend:

1. **Register the spec** (extensions; `parse` fn when the class has
   symbol/anchor structure for the code tier — md/yaml/json anchors are
   built by the fs tier's map builder today, so their `parse` stays null).
2. **Edit side** = a materializer spec in the same family (uniform edit
   verbs, span/keypath splices, named bounces) — until it lands, edits to
   that class route through the review gate (write_review), never raw
   write.
3. **Oracle** = the class's convention (dart: `dart test`; md: docs
   oracle; yaml/json: parse + semantic diff).

No hardcoded `dartFiles` remains: the scan, the tick and the code-tier
dispatch all go through `specForRel`. The model never learns a new verb
per class — `repo_etl` / `meaning_zoom` / `edit_symbol` / `write_review`
stay the closed surface.

The model never writes code tokens; the host derives, materializes, and
verifies.

## Modules

| Path | Role |
| --- | --- |
| `lib/src/test_etl.dart` | ETL-in: failing suite → intent skeletons + DERIVED expectations (declared signatures, or greenfield inference from suite imports/literals). Zero host-authored expectations. |
| `lib/src/dart_materializer.dart` | ETL-out: meaning chains → idiomatic workspace Dart (expression-stack → structured if/else). Unsupported shapes fail as NAMED problems. |
| `lib/src/workspace_meaning_runner.dart` | The runner: derive → model fills bounded slots → derived-expectation replay in-loop → HOST materializes → workspace convention (`dart test`) grades. |
| `lib/src/code_etl.dart` | Repo-scale code ETL (scan → meaning tree → manifest fidelity) + impact-frontier decomposition. Tier 1/2 gates: `etl_scale_tier{1,2}_test.dart`; probe: `tool/etl_scale_probe.dart`. |
| `test/workspace_oracle_e2e_test.dart` | THE R6 gate (ADR 0022 validation). |
| `tool/r6_probe.dart` | Evidence re-run probe (`dart run tool/r6_probe.dart`). |
| `lib/src/span_editor.dart` | **R7b (ADR 0023): the ACT verb** — `edit_symbol` tool (`replace_member_body` / `insert_member` op rows, `apply_executable` pack-fed, built-in lexical `rename_symbol` over the refs frontier). Three host-enforced fences (expressiveness / ORACLE COVERAGE / integration) bounce before generation; atomic batches; failure attribution + in-memory revert; verify baseline is a world resource (`SpanVerifyBaseline`), post-analyze scoped to touched files. Gate: `test/span_edit_gate_test.dart`; packs: `test/pack_edit_gate_test.dart`. |

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
cd pkgs/xsoulspace_agentic_workspace
flutter pub get && dart analyze && flutter test   # or dart test
```

The e2e gate spawns real `dart pub get`/`dart test` subprocesses in a temp
jail (needs network on first run).

## Plan

[ADR 0022](../../docs/decisions/0022_workspace_oracle_meaning_pipeline.md) ·
[R6 in PLAN.md](../xsoulspace_agentic_harness/docs/agent/PLAN.md) ·
[results_r6.md](../xsoulspace_agentic_harness/docs/agent/results_r6.md)
