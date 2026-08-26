// ignore_for_file: avoid_print, lines_longer_than_80_chars

/// M5 ops arm on Apple Foundation Models: native loop, fs tools +
/// `patch_file`, full attribution ledger, verbose decision transcript.
///
/// ```sh
/// dart run bin/coding_suite_afm_ops.dart --task edit_01_rename_constant \
///   [--trace ../../benchmark/runs/afm_ops_edit01.jsonl]
/// ```
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart';

Future<void> main(List<String> args) async {
  var tasksDir = '../xsoulspace_agentic_harness/benchmark/coding_suite/tasks';
  var taskFilter = '';
  String? tracePath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tasks':
        tasksDir = args[++i];
      case '--task':
        taskFilter = args[++i];
      case '--trace':
        tracePath = args[++i];
    }
  }

  final client = AppleFoundationNativeClient();
  await client.load();
  if (!await client.refreshAvailability()) {
    stderr.writeln('Apple Foundation Model unavailable.');
    exit(2);
  }

  attributionDebug = true; // transcript of every decision

  final ledger = AttributionLedger();
  GenerationHandler buildHandler(CodingTask t) => AttributedHandler(
        StructuredToolDecisionHandler(
          inner: DefaultGenerationHandler(
            router: ModelRouter(
              inferenceClientsBuilders: {
                DefaultModelNames.appleFoundation: () => client,
              },
            ),
          ),
        ),
        ledger,
      );

  final allTasks = loadTasks(tasksDir);
  final tasks = allTasks
      .where((t) => t.id.contains(taskFilter))
      .toList();
  if (tasks.isEmpty) {
    stderr.writeln('no task matches "$taskFilter"');
    exit(2);
  }

  final runner = CodingSuiteRunner(
    buildHandler: buildHandler,
    backendLabel: 'afm-ops',
    modelLabel: 'apple-foundation',
    extraTools: [patchFileTool],
  );
  final sw = Stopwatch()..start();
  final result = await runner.runAll(tasks, tracePath: tracePath);
  sw.stop();

  print('\n== transcript summary (${sw.elapsedMilliseconds} ms) ==');
  print(result.toMarkdown(label: 'afm-ops'));
  for (final r in result.results) {
    if (r.passed) continue;
    print('FAIL ${r.taskId} mode=${r.failureMode}');
    for (final c in r.checkerResults.where((c) => !c.passed)) {
      print('  ✗ ${c.detail}');
    }
  }
  print(ledger.report());
}
