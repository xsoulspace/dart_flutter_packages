// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 real-model decomposition probe — Apple Foundation (macOS 26+).
///
/// Thin AFM entrypoint over core's injectable experiment arms
/// (`xsoulspace_inference_core/benchmark/experiment_arms.dart`): this file
/// owns only the availability gate and the per-task handler factory. Arms,
/// markdown table, and JSONL trace live in core via [runDecompositionProbe]:
///
/// 1. **monolithic**: real model acts freely under default ReAct continuation
///    until checkers pass or the tick budget burns.
/// 2. **decomposed-real**: ONE guided decompose call → mechanical execution
///    of every step through the jailed write executor → mechanical per-step
///    verification. LLM called exactly once.
///
/// ```sh
/// cd pkgs/xsoulspace_inference_apple_foundation
/// dart run bin/coding_suite_decomp_probe.dart [--filter refactor] [--trace out.jsonl]
/// ```
library;

import 'dart:io';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart';

Future<void> main(List<String> args) async {
  var tasksDir = '../xsoulspace_agentic_harness/benchmark/coding_suite/tasks';
  var filter = 'refactor';
  var verbose = false;
  String? tracePath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tasks':
        tasksDir = args[++i];
      case '--filter':
        filter = args[++i];
      case '--trace':
        tracePath = args[++i];
      case '--verbose':
        verbose = true;
    }
  }

  final availabilityClient = AppleFoundationNativeClient();
  await availabilityClient.load();
  if (!await availabilityClient.refreshAvailability()) {
    stderr.writeln('Apple Foundation Model unavailable on this device.');
    exit(2);
  }

  final tasks = loadTasks(
    tasksDir,
  ).where((t) => t.id.contains(filter)).toList();

  // Guided act-vs-answer wrapper (same as the Phase 4 suite): tool syntax
  // errors impossible by construction. Fresh native client per task keeps
  // state isolated between runs.
  GenerationHandler buildInner(CodingTask task) {
    final taskClient = AppleFoundationNativeClient();
    return LoggingHandler(
      StructuredToolDecisionHandler(
        inner: DefaultGenerationHandler(
          router: ModelRouter(
            inferenceClientsBuilders: {
              DefaultModelNames.appleFoundation: () => taskClient,
            },
          ),
        ),
      ),
      enabled: verbose,
    );
  }

  await runDecompositionProbe(
    tasks,
    buildInnerHandler: buildInner,
    tracePath: tracePath,
    backendLabel: 'afm',
    modelLabel: 'apple-foundation',
  );
}
