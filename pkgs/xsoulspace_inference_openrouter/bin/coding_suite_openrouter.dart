// ignore_for_file: avoid_print

/// 20-task coding suite against OpenRouter-hosted models.
///
/// ```sh
/// OPENROUTER_API_KEY=sk-... \
/// dart run bin/coding_suite_openrouter.dart [--model z-ai/glm-4.5-air]
///     [--tasks <dir>] [--trace out.jsonl] [--markdown report.md]
///     [--retries 2] [--max-tool-rounds 16] [--filter <substring>]
///     [--resume] [--verbose]
/// ```
///
/// Uses [StructuredToolDecisionHandler] over the OpenRouter backend: every
/// decision is forced through a guided-generation schema (act vs answer), so
/// tool syntax errors are impossible by construction. The backend/model pair
/// is stamped into every trace row so `report.dart` can aggregate runs into a
/// per-category comparison matrix across backends.
library;

import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

import '../../xsoulspace_inference_core/benchmark/coding_suite/runner.dart';
import '../../xsoulspace_inference_core/benchmark/coding_suite/task_spec.dart';

Future<void> main(List<String> args) async {
  var tasksDir = '../xsoulspace_inference_core/benchmark/coding_suite/tasks';
  String? tracePath;
  String? markdownPath;
  var retries = 2;
  var maxToolRounds = 16;
  String? filter;
  var verbose = false;
  var resume = false;
  // Small, cheap, tool-capable default — the suite measures *agentic* quality,
  // not frontier-model ceiling. Override with --model for anything else.
  var model = 'z-ai/glm-4.5-air:free';
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
      case '--api-key':
        apiKey = args[++i];
      case '--resume':
        resume = true;
      case '--verbose':
        verbose = true;
    }
  }

  if (apiKey.isEmpty) {
    stderr.writeln(
      'OPENROUTER_API_KEY env var (or --api-key) is required.',
    );
    exit(2);
  }

  final tasks = loadTasks(tasksDir);
  print('Loaded ${tasks.length} tasks from $tasksDir');
  print('Backend: openrouter — model: $model');

  GenerationHandler buildHandler(CodingTask task) {
    // Fresh client per task keeps HTTP state isolated between runs.
    final taskClient = OpenRouterInferenceClient(
      apiKey: apiKey,
      defaultModel: model,
    );
    return StructuredToolDecisionHandler(
      inner: DefaultGenerationHandler(
        router: ModelRouter(
          inferenceClientsBuilders: {
            OpenRouterModelNames.openRouter: () => taskClient,
          },
        ),
      ),
    );
  }

  GenerationHandler debugHandler(CodingTask task) {
    final innerHandler = buildHandler(task);
    return verbose ? _LoggingHandler(innerHandler) : innerHandler;
  }

  final result = await CodingSuiteRunner(
    buildHandler: debugHandler,
    maxCheckerRetries: retries,
    maxToolRounds: maxToolRounds,
    resumeFromTrace: resume ? tracePath : null,
    backendLabel: 'openrouter',
    modelLabel: model,
  ).runAll(tasks, tracePath: tracePath, filter: filter);

  print(result.toMarkdown(label: 'suite(openrouter:$model)'));
  if (markdownPath != null) {
    File(markdownPath).writeAsStringSync(result.toMarkdown());
  }
  exit(result.passRate == 1 ? 0 : 1);
}

class _LoggingHandler implements GenerationHandler {
  _LoggingHandler(this.inner);
  final GenerationHandler inner;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = await inner.generate(world, request);
    final names = response.toolCalls.map((t) => t.name.value).toList();
    print('[decision] structured=${response.structuredOutput} $names');
    return response;
  }
}
