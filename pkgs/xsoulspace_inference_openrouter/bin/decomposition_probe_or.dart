// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 real-model decomposition probe — OpenRouter backend.
///
/// AFM is environmentally blocked (SensitiveContentAnalysisML 1013); this
/// probe substitutes the Phase 4 OR backend so the decomposition claim gets
/// its real-model measurement. Same arms as coding_suite_decomp_probe.dart:
///
/// 1. **monolithic**: real model acts freely under default ReAct continuation
///    until checkers pass or the round budget burns (`runPlanArm`, baseline).
/// 2. **decomposed-real**: ONE guided decompose call (json_schema: ordered
///    file-write steps with full content) → MECHANICAL execution of every
///    step through the jailed write executor → mechanical per-step
///    verification → termination. LLM called exactly once (+retries).
///
/// ```sh
/// cd pkgs/xsoulspace_inference_openrouter
/// dart run bin/decomposition_probe_or.dart [--filter refactor] [--model m] [--trace out.jsonl]
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

import '../../xsoulspace_inference_core/benchmark/coding_suite/task_spec.dart';
import '../../xsoulspace_inference_core/benchmark/decomposition_experiment.dart';
import '../../xsoulspace_inference_core/benchmark/plan_frontier_arms.dart';

Future<void> main(List<String> args) async {
  var tasksDir = '../xsoulspace_inference_core/benchmark/coding_suite/tasks';
  var filter = 'refactor';
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
    }
  }
  if (model.isEmpty) {
    final config = await EnvConfig.load();
    model = config.get('openrouter.model') ?? 'z-ai/glm-4.5-air:free';
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
      OpenRouterModelNames.openRouter: () => OpenRouterInferenceClient(
            apiKey: apiKey,
            defaultModel: model,
          ),
    },
  );
  final suiteModelId = ModelId('suite-model');
  sharedRouter.models[suiteModelId] =
      Model(id: suiteModelId, name: OpenRouterModelNames.openRouter);

  GenerationHandler buildInner(CodingTask task) =>
      DefaultGenerationHandler(router: sharedRouter);

  final tasks =
      loadTasks(tasksDir).where((t) => t.id.contains(filter)).toList();
  stdout.writeln(
    'ADR 0009 real-model DECOMPOSITION probe (openrouter:$model) — '
    '${tasks.length} tasks\n',
  );

  final b = StringBuffer()
    ..writeln('| task | mono calls | decomp calls | mono cum | decomp cum |'
        ' cum Δ | steps✓ | mono pass | decomp pass | fail-mode |')
    ..writeln('|---|---|---|---|---|---|---|---|---|---|');
  var mcalls = 0, dcalls = 0, mtok = 0, dtok = 0;
  for (final task in tasks) {
    stdout.writeln('▶ ${task.id}');
    final mono = await runPlanArm(
      task,
      planFrontier: false,
      buildHandler: buildInner,
      maxTicks: 2000000,
    );
    stdout.writeln(
      '  monolithic: ${mono.passed ? "PASS" : "FAIL"} — '
      '${mono.llmCalls} calls, cum ${mono.cumulativeTokens} tokens',
    );

    final dec = await runDecomposedArmReal(
      task,
      buildInnerHandler: buildInner,
    );
    stdout.writeln(
      '  decomposed: ${dec.passed ? "PASS" : "FAIL"} — '
      '${dec.llmCalls} call(s), cum ${dec.cumulativeTokens} tokens, '
      'steps verified=${dec.stepsVerified}'
      '${dec.failureMode.isEmpty ? "" : " [${dec.failureMode}]"}',
    );

    mcalls += mono.llmCalls;
    dcalls += dec.llmCalls;
    mtok += mono.cumulativeTokens;
    dtok += dec.cumulativeTokens;
    final delta =
        mono.cumulativeTokens == 0 ? 0.0 : (dec.cumulativeTokens - mono.cumulativeTokens) / mono.cumulativeTokens * 100;
    b.writeln(
      '| ${task.id} | ${mono.llmCalls} | ${dec.llmCalls} '
      '| ${mono.cumulativeTokens} | ${dec.cumulativeTokens} '
      '| ${delta.toStringAsFixed(0)}% | ${dec.stepsVerified} '
      '| ${mono.passed ? '✅' : '❌'} | ${dec.passed ? '✅' : '❌'} '
      '| ${dec.failureMode.isEmpty ? '—' : dec.failureMode} |',
    );
    if (tracePath != null) {
      File(tracePath).writeAsStringSync(
        jsonEncode({
          'task_id': task.id,
          'arm': 'monolithic',
          'passed': mono.passed,
          'llm_calls': mono.llmCalls,
          'cumulative_tokens': mono.cumulativeTokens,
        }) + '\n',
        mode: FileMode.append,
      );
      File(tracePath).writeAsStringSync(
        jsonEncode({
          'task_id': task.id,
          'arm': 'decomposed-real',
          'passed': dec.passed,
          'llm_calls': dec.llmCalls,
          'cumulative_tokens': dec.cumulativeTokens,
          'steps_verified': dec.stepsVerified,
          'failure_mode': dec.failureMode,
        }) + '\n',
        mode: FileMode.append,
      );
    }
  }

  b..writeln()
    ..writeln('**Totals** — calls: $mcalls → $dcalls '
        '(${((dcalls - mcalls) / (mcalls == 0 ? 1 : mcalls) * 100).toStringAsFixed(0)}%), '
        'cum tokens: $mtok → $dtok '
        '(${((dtok - mtok) / (mtok == 0 ? 1 : mtok) * 100).toStringAsFixed(0)}%)')
    ..writeln()
    ..writeln('decomposed arm = ONE guided decompose call + fully mechanical '
        'execution/verification.');
  stdout.writeln(b);
}
