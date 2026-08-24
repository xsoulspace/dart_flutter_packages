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
  var arms = 'both';
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

  final rows = <(PlanRow?, PlanRow?)>[];
  for (final task in tasks) {
    stdout.writeln('▶ ${task.id}');
    PlanRow? baseline;
    PlanRow? plan;
    if (arms != 'plan') {
      baseline = await runPlanArm(
        task,
        planFrontier: false,
        buildHandler: buildHandler,
        maxTicks: 2000000,
      );
      stdout.writeln(
        '  baseline: ${baseline.passed ? "PASS" : "FAIL"} — '
        '${baseline.llmCalls} calls, '
        'cum ${baseline.cumulativeTokens} tokens',
      );
    }
    if (arms != 'baseline') {
      plan = await runPlanArm(
        task,
        planFrontier: true,
        buildHandler: buildHandler,
        maxTicks: 2000000,
      );
      stdout.writeln(
        '  plan:     ${plan.passed ? "PASS" : "FAIL"} — '
        '${plan.llmCalls} calls, cum ${plan.cumulativeTokens} tokens',
      );
    }
    rows.add((baseline, plan));
  }

  final tagLabel = ContextFragmentProtocol.roleTagsEnabled ? 'tags-on' : 'tags-OFF';
  final b = StringBuffer()
    ..writeln()
    ..writeln('(role tags: $tagLabel)')
    ..writeln('| task | base calls | plan calls | base cum tokens | plan cum tokens |'
        ' cum Δ | pass |')
    ..writeln('|---|---|---|---|---|---|---|');
  var baseTok = 0, planTok = 0, baseCalls = 0, planCalls = 0;
  var allPass = true;
  for (final (br, pr) in rows) {
    if (br != null) {
      baseTok += br.cumulativeTokens;
      baseCalls += br.llmCalls;
      allPass &= br.passed;
    }
    if (pr != null) {
      planTok += pr.cumulativeTokens;
      planCalls += pr.llmCalls;
      allPass &= pr.passed;
    }
    final id = (br ?? pr)!.taskId;
    final delta = br == null || pr == null || br.cumulativeTokens == 0
        ? null
        : ((pr.cumulativeTokens - br.cumulativeTokens) /
              br.cumulativeTokens *
              100);
    b.writeln(
      '| $id '
      '| ${br?.llmCalls ?? '—'} | ${pr?.llmCalls ?? '—'} '
      '| ${br?.cumulativeTokens ?? '—'} | ${pr?.cumulativeTokens ?? '—'} '
      '| ${delta == null ? '—' : '${delta.toStringAsFixed(0)}%'} '
      '| ${(br?.passed ?? true) && (pr?.passed ?? true) ? '✅' : '❌'} |',
    );
    for (final r in [br, pr]) {
      if (r == null || tracePath == null) continue;
      File(tracePath).writeAsStringSync(
        jsonEncode({
          'task_id': r.taskId,
          'arm': identical(r, br) ? 'baseline' : 'plan',
          'role_tags': ContextFragmentProtocol.roleTagsEnabled,
          'passed': r.passed,
          'llm_calls': r.llmCalls,
          'tokens_used_last_cut': r.tokensUsed,
          'cumulative_tokens': r.cumulativeTokens,
          'wall_ms': r.wallMs,
        }) + '\n',
        mode: FileMode.append,
      );
    }
  }
  b..writeln('')
    ..writeln('**Totals (CUMULATIVE tokens)** — calls: $baseCalls → $planCalls'
        '${arms == 'both' ? ' (${((planCalls - baseCalls) / (baseCalls == 0 ? 1 : baseCalls) * 100).toStringAsFixed(0)}%)' : ''}, '
        'tokens: $baseTok → $planTok'
        '${arms == 'both' && baseTok > 0 ? ' (${((planTok - baseTok) / baseTok * 100).toStringAsFixed(0)}%)' : ''}')
    ..writeln()
    ..writeln(allPass
        ? 'All runs passed — comparison fully valid.'
        : '⚠️ some tasks failed — treat deltas as indicative only.');

  stdout.writeln(b);
}
