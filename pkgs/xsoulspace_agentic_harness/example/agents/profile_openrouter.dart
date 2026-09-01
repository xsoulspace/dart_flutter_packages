// ignore_for_file: avoid_print, lines_longer_than_80_chars

/// M5 real-model runner: OpenRouter native loop through the ops arm with
/// M1 attribution. Native tool calling only — guided schema is excluded
/// by design (measured 0/20; see results_comparison.md).
///
/// ```sh
/// OPENROUTER_API_KEY=sk-... dart run example/agents/profile_openrouter.dart \
///   --tasks ../../benchmark/coding_suite/tasks --filter edit_01 [--ops] [--trace out.jsonl]
/// ```
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FsToolsRoot, writeTool;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/attribution.dart'
    as attr;

Future<void> main(List<String> args) async {
  var tasksDir = '../../benchmark/coding_suite/tasks';
  var filter = '';
  String? tracePath;
  var model = '';
  var ops = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tasks':
        tasksDir = args[++i];
      case '--filter':
        filter = args[++i];
      case '--model':
        model = args[++i];
      case '--ops':
        ops = true;
      case '--trace':
        tracePath = args[++i];
    }
  }

  var apiKey = Platform.environment['OPENROUTER_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    final config = await EnvConfig.load();
    apiKey = config.get('OPENROUTER_API_KEY') ?? '';
  }
  if (apiKey.isEmpty) {
    stderr.writeln('No OPENROUTER_API_KEY found.');
    exit(2);
  }
  if (model.isEmpty) {
    final config = await EnvConfig.load();
    model = config.get('openrouter.model') ?? 'deepseek/deepseek-v4-flash-0731';
  }

  final router = ModelRouter(
    inferenceClientsBuilders: {
      OpenRouterModelNames.openRouter: () =>
          OpenRouterInferenceClient(apiKey: apiKey, defaultModel: model),
      // Runner binds actors via DefaultModelNames; resolve either way.
      DefaultModelNames.appleFoundation: () =>
          OpenRouterInferenceClient(apiKey: apiKey, defaultModel: model),
    },
  );
  final id = ModelId('profile-model');
  router.models[id] = Model(id: id, name: OpenRouterModelNames.openRouter);

  final tasks = loadTasks(
    tasksDir,
  ).where((t) => filter.isEmpty || t.id.contains(filter)).toList();
  if (tasks.isEmpty) {
    stderr.writeln('no tasks matched "$filter"');
    exit(2);
  }
  if (args.contains('--debug')) attr.attributionDebug = true;
  print(
    'profile(openrouter:$model native) — ${tasks.length} task(s), '
    "tools=${ops ? 'fs+write' : 'fs'}\n",
  );

  final report = await runProfile(
    tasks,
    buildHandler: (_) => DefaultGenerationHandler(router: router),
    // B4 hard cut: the legacy patch_file tool is deleted; the ops-arm
    // equivalent surface is the jailed `write` tool.
    extraTools: ops ? [(root) => writeTool(FsToolsRoot(root))] : const [],
    tracePath: tracePath,
  );
  print(report);
}
