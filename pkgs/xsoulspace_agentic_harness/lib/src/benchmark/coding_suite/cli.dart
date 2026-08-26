// ignore_for_file: avoid_print

/// CLI entry for the 20-task coding suite.
///
/// Usage:
///
/// ```
/// dart run benchmark/coding_suite/cli.dart [--tasks <dir>] [--trace out.jsonl]
///                                            [--markdown report.md]
/// ```
///
/// The handler is chosen by `--backend`:
/// - `afm` (default): Apple Foundation via the native client (macOS only).
/// - `scripted`: deterministic canned handler — no LLM, used to validate the
///   pipeline itself and in CI.
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'runner.dart';
import 'scripted_handler.dart';
import 'task_spec.dart';

Future<void> main(List<String> args) async {
  var tasksDir = 'benchmark/coding_suite/tasks';
  String? tracePath;
  String? markdownPath;
  var backend = 'scripted';
  var retries = 0;
  var maxToolRounds = 16;
  String? filter;
  var resume = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tasks':
        tasksDir = args[++i];
      case '--trace':
        tracePath = args[++i];
      case '--markdown':
        markdownPath = args[++i];
      case '--backend':
        backend = args[++i];
      case '--retries':
        retries = int.parse(args[++i]);
      case '--max-tool-rounds':
        maxToolRounds = int.parse(args[++i]);
      case '--filter':
        filter = args[++i];
      case '--resume':
        resume = true;
    }
  }

  final tasks = loadTasks(tasksDir);
  stdout.writeln('Loaded ${tasks.length} tasks from $tasksDir');

  GenerationHandler buildHandler(CodingTask task) {
    if (backend == 'afm') {
      // AFM wiring lives in xsoulspace_inference_apple_foundation; import it
      // there and pass a custom --handler. Kept out of core to preserve the
      // pure-Dart boundary.
      throw UnimplementedError(
        'Use the apple_foundation package runner for --backend afm '
        '(see pkgs/xsoulspace_inference_apple_foundation/bin/).',
      );
    }
    return ScriptedSuiteHandler(taskId: task.id);
  }

  final result = await CodingSuiteRunner(
    buildHandler: buildHandler,
    maxCheckerRetries: retries,
    maxToolRounds: maxToolRounds,
    resumeFromTrace: (resume && tracePath != null) ? tracePath : null,
    backendLabel: 'scripted',
    modelLabel: 'scripted',
  ).runAll(tasks, tracePath: tracePath, filter: filter);

  stdout.writeln(result.toMarkdown(label: 'suite($backend)'));
  if (markdownPath != null) {
    File(markdownPath).writeAsStringSync(result.toMarkdown());
  }
  exit(result.passRate == 1 ? 0 : 1);
}
