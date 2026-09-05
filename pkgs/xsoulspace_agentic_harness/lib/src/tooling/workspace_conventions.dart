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
/// 2. Dart package WITHOUT tests → `null` (honest failure). R5 finding:
///    `dart analyze` passes trivially before any work (exit 0 on a clean
///    empty package), so it can never be the done-criterion for a task that
///    must PRODUCE something. The delegator passes `--check` explicitly, or
///    the actor proposes one via `declare_check` (M0b).
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
    // ADR 0027 dogfood fix (measured: root `dart test` exit=65): a
    // WORKSPACE root pubspec resolves through Flutter packages — grade
    // via `flutter test`.
    if (pubspec.readAsStringSync().contains('workspace:')) {
      if (_hasTests(root)) return const ['flutter', 'test'];
      return const ['flutter', 'analyze'];
    }
    // R7 fix (measured: harnessd gate, dart test exit=65 on a Flutter
    // package): Flutter packages must be graded by `flutter test` — pure
    // `dart test` cannot resolve flutter_test and fails every run.
    if (isFlutterPackage(pubspec)) {
      if (_hasTests(root)) return const ['flutter', 'test'];
      return const ['flutter', 'analyze'];
    }
    if (_hasTests(root)) return const ['dart', 'test'];
    // R5 finding: analyze-only passes trivially (0 decisions) on a clean
    // package — it proves nothing about the task. Honest null.
    return null;
  }
  if (main.existsSync()) return const ['dart', 'run', 'main.dart'];
  return null;
}

/// A Flutter package declares the Flutter SDK in its pubspec (`sdk: flutter`
/// under dependencies or a `flutter:` section).
bool isFlutterPackage(File pubspec) {
  final src = pubspec.readAsStringSync();
  return src.contains('sdk: flutter') ||
      RegExp(r'^flutter:', multiLine: true).hasMatch(src);
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
