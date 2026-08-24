// ignore_for_file: avoid_print

/// CLI bridge used by external benchmark drivers to evaluate task checkers.
library;

import 'dart:io';
import 'dart:convert';

import 'checkers.dart';
import 'task_spec.dart';

Future<void> main(List<String> args) async {
  String? taskPath;
  String? workspacePath;
  for (var index = 0; index < args.length; index += 2) {
    if (index + 1 >= args.length) {
      _fail('missing value for ${args[index]}');
    }
    switch (args[index]) {
      case '--task':
        taskPath = args[index + 1];
      case '--workspace':
        workspacePath = args[index + 1];
      default:
        _fail('unknown argument: ${args[index]}');
    }
  }
  if (taskPath == null || workspacePath == null) {
    _fail('usage: dart run benchmark/coding_suite/check_workspace.dart '
        '--task <yaml-path> --workspace <dir>');
  }

  final CodingTask task;
  try {
    task = CodingTask.fromYaml(File(taskPath).readAsStringSync());
  } catch (error) {
    _fail('invalid task $taskPath: $error');
  }

  final results = [
    for (final checker in task.checkers) evaluateChecker(checker, workspacePath),
  ];
  final passed = results.every((result) => result.passed);
  print(
    const JsonEncoder.withIndent('  ').convert({
      'task_id': task.id,
      'passed': passed,
      'results': [
        for (final result in results)
          {'passed': result.passed, 'detail': result.detail},
      ],
    }),
  );
  exit(passed ? 0 : 1);
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}
