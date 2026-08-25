// ignore_for_file: lines_longer_than_80_chars

/// 20-task coding suite against real Apple Foundation Models (macOS only).
///
/// ```sh
/// dart run bin/coding_suite_afm.dart [--tasks <dir>] [--trace out.jsonl]
///     [--markdown report.md] [--retries 2]
/// ```
///
/// Uses [StructuredToolDecisionHandler] over the AFM backend: every decision
/// is forced through a guided-generation schema (act vs answer), so tool
/// syntax errors are impossible by construction. Failing checkers are fed
/// back mechanically as new decisions, bounded by `--retries`.
///
/// Artifacts match the scripted/pi runs (JSONL trace + markdown table) so
/// results stay apples-to-apples.
library;

import 'dart:io';

import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import '../../xsoulspace_inference_core/benchmark/coding_suite/runner.dart';
import '../../xsoulspace_inference_core/benchmark/coding_suite/task_spec.dart';
import '../../xsoulspace_inference_core/benchmark/shared/logging_handler.dart';

Future<void> main(List<String> args) async {
  var tasksDir = '../xsoulspace_inference_core/benchmark/coding_suite/tasks';
  String? tracePath;
  String? markdownPath;
  var retries = 2;
  var maxToolRounds = 16;
  String? filter;
  var verbose = false;
  var resume = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tasks':
        tasksDir = args[++i];
      case '--trace':
        tracePath = args[++i];
      case '--markdown':
        markdownPath = args[++i];
      case '--retries':
        retries = int.parse(args[++i]);
      case '--max-tool-rounds':
        maxToolRounds = int.parse(args[++i]);
      case '--filter':
        filter = args[++i];
      case '--resume':
        resume = true;
      case '--verbose':
        verbose = true;
    }
  }

  final client = AppleFoundationNativeClient();
  await client.load();
  if (!await client.refreshAvailability()) {
    stderr.writeln('Apple Foundation Model unavailable on this device.');
    exit(2);
  }

  final tasks = loadTasks(tasksDir);
  stdout.writeln('Loaded ${tasks.length} tasks from $tasksDir');

  GenerationHandler buildHandler(CodingTask task) {
    // Fresh native client per task keeps state isolated between runs.
    final taskClient = AppleFoundationNativeClient();
    return StructuredToolDecisionHandler(
      inner: DefaultGenerationHandler(
        router: ModelRouter(
          inferenceClientsBuilders: {
            DefaultModelNames.appleFoundation: () => taskClient,
          },
        ),
      ),
    );
  }

  GenerationHandler debugHandler(CodingTask task) {
    final innerHandler = buildHandler(task);
    return verbose ? LoggingHandler(innerHandler, enabled: true) : innerHandler;
  }

  final result = await CodingSuiteRunner(
    buildHandler: debugHandler,
    maxCheckerRetries: retries,
    maxToolRounds: maxToolRounds,
    resumeFromTrace: resume ? tracePath : null,
    backendLabel: 'afm',
    modelLabel: 'apple-foundation',
  ).runAll(tasks, tracePath: tracePath, filter: filter);

  stdout.writeln(result.toMarkdown(label: 'suite(afm)'));
  if (markdownPath != null) {
    File(markdownPath).writeAsStringSync(result.toMarkdown());
  }
  exit(result.passRate == 1 ? 0 : 1);
}
