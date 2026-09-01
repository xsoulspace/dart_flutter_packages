// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 real-model probe — plan-frontier vs ReAct close-out against
/// Apple Foundation Models (macOS 26+ only).
///
/// Thin AFM entrypoint over core's injectable experiment arms
/// (`xsoulspace_inference_core/benchmark/experiment_arms.dart`): this file
/// owns only the availability gate and the per-task handler factory (guided
/// act-vs-answer decisions, fresh native client per task — identical to the
/// Phase 4 suite). Arm loop, markdown table, and JSONL trace live in core.
///
/// ```sh
/// cd pkgs/xsoulspace_inference_apple_foundation
/// dart run bin/coding_suite_plan_probe.dart [--filter edit] [--trace out.jsonl]
/// ```
library;

import 'dart:io';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart';

Future<void> main(List<String> args) async {
  var tasksDir = '../xsoulspace_agentic_harness/benchmark/coding_suite/tasks';
  var filter = 'edit';
  var arms = 'both';
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
      case '--arms':
        arms = args[++i]; // baseline | plan | both
      case '--no-role-tags':
        // Phase-4 wire format — prompt-format A/B scaffold.
        ContextFragmentProtocol.roleTagsEnabled = false;
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

  GenerationHandler buildHandler(CodingTask task) {
    // Fresh native client per task keeps state isolated between runs.
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

  await runPlanProbe(
    tasks,
    buildHandler: buildHandler,
    tracePath: tracePath,
    arms: arms,
    backendLabel: 'afm',
    modelLabel: 'apple-foundation',
  );
}
