// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 real-model decomposition probe — OpenRouter backend.
///
/// Thin OR entrypoint over core's injectable experiment arms
/// (`xsoulspace_inference_core/benchmark/experiment_arms.dart`): this file
/// owns only model/key resolution and the shared router. Arms, markdown
/// table, and JSONL trace live in core via [runDecompositionProbe]:
///
/// 1. **monolithic**: real model acts freely under default ReAct continuation
///    until checkers pass or the tick budget burns.
/// 2. **decomposed-real**: ONE guided decompose call (ordered file-write
///    steps with full content) → MECHANICAL execution of every step through
///    the jailed write executor → mechanical per-step verification. LLM
///    called exactly once (+retries).
///
/// ```sh
/// cd pkgs/xsoulspace_inference_openrouter
/// dart run bin/decomposition_probe_or.dart [--filter refactor] [--model m] [--trace out.jsonl]
/// ```
library;

import 'dart:io';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart';

Future<void> main(List<String> args) async {
  var tasksDir = '../xsoulspace_agentic_harness/benchmark/coding_suite/tasks';
  var filter = 'refactor';
  var verbose = false;
  var model = '';
  var apiKey = Platform.environment['OPENROUTER_API_KEY'] ?? '';
  String? tracePath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tasks':
        tasksDir = args[++i];
      case '--filter':
        filter = args[++i];
      case '--model':
        model = args[++i];
      case '--api-key':
        apiKey = args[++i];
      case '--trace':
        tracePath = args[++i];
      case '--verbose':
        verbose = true;
    }
  }
  if (model.isEmpty) {
    final config = await EnvConfig.load();
    model = config.get('openrouter.model') ?? 'deepseek/deepseek-v4-flash-0731';
  }
  if (apiKey.isEmpty) {
    final config = await EnvConfig.load();
    apiKey = config.get('OPENROUTER_API_KEY') ?? '';
  }
  if (apiKey.isEmpty) {
    stderr.writeln('No OPENROUTER_API_KEY found.');
    exit(2);
  }

  // ONE shared router for both arms: handler-side resolution must find the
  // same model id the arms bind actors to ('suite-model').
  final sharedRouter = ModelRouter(
    inferenceClientsBuilders: {
      OpenRouterModelNames.openRouter: () =>
          OpenRouterInferenceClient(apiKey: apiKey, defaultModel: model),
    },
  );
  final suiteModelId = ModelId('suite-model');
  sharedRouter.models[suiteModelId] = Model(
    id: suiteModelId,
    name: OpenRouterModelNames.openRouter,
  );

  GenerationHandler buildInner(CodingTask task) => LoggingHandler(
    DefaultGenerationHandler(router: sharedRouter),
    enabled: verbose,
  );

  final tasks = loadTasks(
    tasksDir,
  ).where((t) => t.id.contains(filter)).toList();

  await runDecompositionProbe(
    tasks,
    buildInnerHandler: buildInner,
    tracePath: tracePath,
    backendLabel: 'openrouter',
    modelLabel: model,
  );
}
