// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 real-model probe — plan-frontier vs ReAct close-out against
/// Apple Foundation Models (macOS only).
///
/// The scripted falsification (`xsoulspace_inference_core/benchmark/
/// plan_falsification_experiment.dart`) proved the harness mechanics:
/// −39% LLM calls, −19% tokens/task at equal pass rate. Open question: does a
/// REAL local model re-spend the saved close-out call elsewhere? This script
/// answers it on the `edit` tasks, both arms, same AFM backend, same guided
/// decision machinery as the Phase 4 suite.
///
/// ```sh
/// cd pkgs/xsoulspace_inference_apple_foundation
/// dart run bin/coding_suite_plan_probe.dart [--filter edit] [--trace out.jsonl]
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import '../../xsoulspace_inference_core/benchmark/plan_frontier_arms.dart';
import '../../xsoulspace_inference_core/benchmark/coding_suite/task_spec.dart';

Future<void> main(List<String> args) async {
  var tasksDir = '../xsoulspace_inference_core/benchmark/coding_suite/tasks';
  var filter = 'edit';
  String? tracePath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tasks':
        tasksDir = args[++i];
      case '--filter':
        filter = args[++i];
      case '--trace':
        tracePath = args[++i];
    }
  }

  final availabilityClient = AppleFoundationNativeClient();
  await availabilityClient.load();
  if (!await availabilityClient.refreshAvailability()) {
    stderr.writeln('Apple Foundation Model unavailable on this device.');
    exit(2);
  }

  final tasks =
      loadTasks(tasksDir).where((t) => t.id.contains(filter)).toList();
  stdout.writeln(
    'ADR 0009 real-model probe — ${tasks.length} tasks, backend=afm\n',
  );

  // Same guided-decision machinery as the Phase 4 suite: every decision is
  // forced through an act-vs-answer schema so tool syntax errors are
  // impossible by construction. Fresh native client per task.
  GenerationHandler buildHandler(CodingTask task) {
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

  final rows = <(PlanRow, PlanRow)>[];
  for (final task in tasks) {
    stdout.writeln('▶ ${task.id}');
    final baseline = await runPlanArm(
      task,
      planFrontier: false,
      buildHandler: buildHandler,
      maxTicks: 2000000,
    );
    stdout.writeln(
      '  baseline: ${baseline.passed ? "PASS" : "FAIL"} — '
      '${baseline.llmCalls} calls, ${baseline.tokensUsed} tokens',
    );
    final plan = await runPlanArm(
      task,
      planFrontier: true,
      buildHandler: buildHandler,
      maxTicks: 2000000,
    );
    stdout.writeln(
      '  plan:     ${plan.passed ? "PASS" : "FAIL"} — '
      '${plan.llmCalls} calls, ${plan.tokensUsed} tokens',
    );
    rows.add((baseline, plan));
  }

  final b = StringBuffer()
    ..writeln()
    ..writeln('| task | base calls | plan calls | base tokens | plan tokens |'
        ' token Δ | pass |')
    ..writeln('|---|---|---|---|---|---|---|');
  var baseTok = 0, planTok = 0, baseCalls = 0, planCalls = 0;
  var allPass = true;
  for (final (br, pr) in rows) {
    allPass &= br.passed && pr.passed;
    baseTok += br.tokensUsed;
    planTok += pr.tokensUsed;
    baseCalls += br.llmCalls;
    planCalls += pr.llmCalls;
    final delta = br.tokensUsed == 0
        ? 0
        : ((pr.tokensUsed - br.tokensUsed) / br.tokensUsed * 100);
    b.writeln(
      '| ${br.taskId} | ${br.llmCalls} | ${pr.llmCalls} '
      '| ${br.tokensUsed} | ${pr.tokensUsed} | ${delta.toStringAsFixed(0)}% '
      '| ${(br.passed && pr.passed) ? '✅' : '❌'} |',
    );
    if (tracePath != null) {
      File(tracePath).writeAsStringSync(
        '${jsonEncode({
          'task_id': br.taskId,
          'arm': 'baseline',
          'passed': br.passed,
          'llm_calls': br.llmCalls,
          'tokens_used': br.tokensUsed,
          'wall_ms': br.wallMs,
        })}\n',
        mode: FileMode.append,
      );
      File(tracePath).writeAsStringSync(
        '${jsonEncode({
          'task_id': pr.taskId,
          'arm': 'plan',
          'passed': pr.passed,
          'llm_calls': pr.llmCalls,
          'tokens_used': pr.tokensUsed,
          'wall_ms': pr.wallMs,
        })}\n',
        mode: FileMode.append,
      );
    }
  }
  b..writeln('')
    ..writeln('**Totals** — calls: $baseCalls → $planCalls '
        '(${((planCalls - baseCalls) / (baseCalls == 0 ? 1 : baseCalls) * 100).toStringAsFixed(0)}%), '
        'tokens: $baseTok → $planTok '
        '(${((planTok - baseTok) / (baseTok == 0 ? 1 : baseTok) * 100).toStringAsFixed(0)}%)')
    ..writeln()
    ..writeln(allPass
        ? 'Both arms pass — comparison valid.'
        : '⚠️ some tasks failed — treat deltas as indicative only.');

  stdout.writeln(b);
}
