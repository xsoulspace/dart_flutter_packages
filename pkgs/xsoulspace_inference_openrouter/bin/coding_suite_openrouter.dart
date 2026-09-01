// ignore_for_file: avoid_print

/// 20-task coding suite against OpenRouter-hosted models.
///
/// ```sh
/// OPENROUTER_API_KEY=sk-... \
/// dart run bin/coding_suite_openrouter.dart [--model z-ai/glm-4.5-air]
///     [--decision guided|native]
///     [--tasks <dir>] [--trace out.jsonl] [--markdown report.md]
///     [--retries 2] [--max-tool-rounds 16] [--filter <substring>]
///     [--resume] [--verbose]
/// ```
///
/// Uses native provider tool calling by default (ADR 0013); pass
/// `--decision guided` to force every decision through an act-vs-answer
/// guided-generation schema instead (for A/B only — guided scored 0/20 vs
/// native 6/20 on the same model). The backend/model pair is stamped into
/// every trace row so `report.dart` can aggregate runs into a per-category
/// comparison matrix across backends.
library;

import 'dart:async';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart';

Future<void> main(List<String> args) async {
  var tasksDir = '../xsoulspace_agentic_harness/benchmark/coding_suite/tasks';
  String? tracePath;
  String? markdownPath;
  var retries = 2;
  var maxToolRounds = 16;
  String? filter;
  var verbose = false;
  var resume = false;
  var decision = 'native';
  // Small, cheap, tool-capable default — the suite measures *agentic* quality,
  // not frontier-model ceiling. Override with --model for anything else.
  var model = '';
  var apiKey = Platform.environment['OPENROUTER_API_KEY'] ?? '';
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
      case '--model':
        model = args[++i];
      case '--decision':
        decision = args[++i];
      case '--api-key':
        apiKey = args[++i];
      case '--resume':
        resume = true;
      case '--verbose':
        verbose = true;
    }
  }

  if (model.isEmpty) {
    // --model flag wins; otherwise the saved local/global config.
    final config = await EnvConfig.load();
    model = config.get('openrouter.model') ?? 'deepseek/deepseek-v4-flash-0731';
  }

  if (apiKey.isEmpty) {
    // Fall through to saved config (local project scope, then global).
    final config = await EnvConfig.load();
    apiKey = config.get('OPENROUTER_API_KEY') ?? '';
  }

  if (apiKey.isEmpty) {
    stderr.writeln(
      'No OpenRouter API key found. Provide one via --api-key or the '
      'OPENROUTER_API_KEY environment variable, or persist it in '
      '${EnvConfig.defaultLocalPath()} (project) / '
      '${EnvConfig.defaultGlobalPath()} (machine) as '
      '{"OPENROUTER_API_KEY": "sk-..."}.',
    );
    exit(2);
  }

  if (decision != 'guided' && decision != 'native') {
    stderr.writeln('--decision must be "guided" or "native"');
    exit(2);
  }

  final tasks = loadTasks(tasksDir);
  print('Loaded ${tasks.length} tasks from $tasksDir');
  print('Backend: openrouter — model: $model — decision: $decision');

  // ONE router shared by handler and runner — model resolution cannot
  // desynchronize (see CodingSuiteRunner.router doc).
  //
  // Default is native tool calling (ADR 0013). `--decision guided` opt-in
  // wraps the native handler in StructuredToolDecisionHandler for A/B only.
  // OpenRouter client uses the native chat-completions messages codec
  // (useMessagesCodec default true, C1 fix).
  final sharedRouter = ModelRouter(
    inferenceClientsBuilders: {
      OpenRouterModelNames.openRouter: () => OpenRouterInferenceClient(
        apiKey: apiKey,
        defaultModel: model,
        useMessagesCodec: true,
      ),
    },
  );

  GenerationHandler buildHandler(CodingTask task) {
    final inner = DefaultGenerationHandler(router: sharedRouter);
    return decision == 'guided'
        ? StructuredToolDecisionHandler(inner: inner, registryName: 'default')
        : inner;
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
    router: sharedRouter,
    backendLabel: 'openrouter-$decision',
    modelName: OpenRouterModelNames.openRouter,
    modelLabel: model,
  ).runAll(tasks, tracePath: tracePath, filter: filter);

  print(result.toMarkdown(label: 'suite(openrouter:$model)'));
  if (markdownPath != null) {
    File(markdownPath).writeAsStringSync(result.toMarkdown());
  }
  exit(result.passRate == 1 ? 0 : 1);
}
