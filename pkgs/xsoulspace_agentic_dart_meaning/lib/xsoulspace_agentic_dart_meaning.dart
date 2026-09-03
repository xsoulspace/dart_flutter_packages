/// Dart domain host for the agentic harness (ADR 0022).
///
/// The meaning pipeline grades through the **workspace oracle**:
///
/// 1. [deriveWorkspaceIntents] — ETL-in: the workspace's own test suite is
///    the expectation table. Analyzer-driven, deterministic, LLM-free —
///    zero host-authored expectations (the R6/A-closure fix).
/// 2. `materializeWorkspaceDart` — ETL-out: meaning-tree op chains compile
///    to idiomatic workspace Dart (typed signatures, real file targets), so
///    `dart test` — not a VM replay — is the final gate (the C-closure fix).
/// 3. [runWorkspaceMeaningAgent] — the runner: derive → model fills bounded
///    slots via `intent_define` → mechanical in-loop replay → host
///    materializes → workspace convention grades.
///
/// The closed vocabulary is the harness core's (`meaningExecutorOps`); this
/// host never widens it outside the ADR 0019 §4 data-plus-verification
/// mechanism. VM-replay (`program.dart`) stays the interpreter-parity
/// oracle; this package owns the workspace-Dart realization.
library;

export 'src/code_etl.dart';
export 'src/repo_etl_tool.dart';
export 'src/dart_materializer.dart';
export 'src/test_etl.dart';
export 'src/workspace_meaning_runner.dart';
