// ignore_for_file: lines_longer_than_80_chars

/// Stage M0 / D8 — the default coding oracle is the **workspace convention**,
/// resolved mechanically from the jail (LLM-free, zero per-task code).
///
/// Hardcoded per-task checkers conflated the *criterion* (what proves the
/// task done — ADR 0009: part of the goal vector) with the *executor* (run a
/// command → exit-0 — generic, `RunGoalSpec`). This resolver supplies the
/// criterion for a free task sentence the same way pi implicitly does: the
/// project's own conventions decide what "done" means.
///
/// Resolution order (first match wins):
/// 1. Dart package (`pubspec.yaml`) with tests (`test/**/*_test.dart`)
///    → `dart test` (compilation errors fail the run — analyze is implied).
/// 2. Dart package without tests → `dart analyze` (static gate; honest and
///    mechanical, weaker than a run — the host may override with `--check`).
/// 3. Bare `main.dart` (no pubspec) → `dart run main.dart` (the PROVEN
///    gate_run terminal proof).
/// 4. Nothing resolvable → `null` (the host must fail honestly — never
///    invent a criterion the workspace does not declare).
library;

import 'dart:io';

/// Returns the check command for the workspace at [root], or `null` when no
/// convention resolves. Pure fs inspection; never mutates the workspace.
List<String>? resolveWorkspaceCheck(Directory root) {
  if (!root.existsSync()) return null;
  final pubspec = File('${root.path}/pubspec.yaml');
  final isDartPackage = pubspec.existsSync();
  final main = File('${root.path}/main.dart');

  if (isDartPackage) {
    if (_hasTests(root)) return const ['dart', 'test'];
    return const ['dart', 'analyze'];
  }
  if (main.existsSync()) return const ['dart', 'run', 'main.dart'];
  return null;
}

bool _hasTests(Directory root) {
  final testDir = Directory('${root.path}/test');
  if (!testDir.existsSync()) return false;
  return testDir
      .listSync(recursive: true)
      .whereType<File>()
      .any((f) => f.path.endsWith('_test.dart'));
}

/// Splits a `--check <command>` value into argv shell-words (no shell
/// interpolation — the command runs via `Process.run` without a shell, so
/// quoting is literal and injection is impossible by construction).
List<String> splitCheckCommand(String raw) =>
    raw.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
