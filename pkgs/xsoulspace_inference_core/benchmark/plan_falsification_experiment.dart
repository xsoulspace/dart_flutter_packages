// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 falsifying experiment — "goals as vectors, plans as projections".
///
/// Question (verbatim from the ADR): take one coding-suite task, express its
/// steps with checker-based success criteria, run the loop where mechanical
/// steps skip the LLM entirely, and measure the tokens/task delta. If the
/// delta is noise, the idea dies cheaply.
///
/// Two arms, identical task fixtures, identical canned model behavior (same
/// writes), same deterministic checkers:
///
/// - **baseline**: current harness path. Every tool-result triggers a ReAct
///   continuation decision (ADR 0005), so the model is called once more than
///   it has actions — the last call exists only to produce a narrative close.
/// - **plan-driven**: goal criteria live in the graph as a Goal + step
///   entities; a mechanical frontier policy evaluates the success predicates
///   itself when a tool result lands. Verified goal ⇒ no continuation decision
///   ⇒ the loop idles without ever asking the model whether it finished.
///   Failed predicates open ONE tight continuation (mechanical checker
///   feedback, same information budget as the suite's verifier loop).
///
/// Known deviation from the full ADR 0009 design: the frontier policy here
/// reads the jail filesystem directly. In the real design predicates run as
/// verifier tools behind seam 3 and their results become beats, keeping the
/// policy pure. This shortcut is acceptable for measuring the token delta;
/// it is NOT the production shape.
///
/// Run: `dart run benchmark/plan_falsification_experiment.dart`
library;


import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'coding_suite/scripted_handler.dart';
import 'coding_suite/task_spec.dart';


import 'plan_frontier_arms.dart';

/// Emits exactly one canned action per generation call — unlike
/// [ScriptedSuiteHandler] which dumps every step plus a narrative close in
/// one call. Mirrors how a real model behaves across continuation rounds.
class OneActionPerCallHandler implements GenerationHandler {
  OneActionPerCallHandler({required this.taskId});
  final String taskId;
  int _next = 0;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final steps = scriptedBehaviors[taskId]!;
    if (_next < steps.length) {
      final step = steps[_next++];
      final response = ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: {'text': 'step $_next'},
        rawOutput: 'step $_next',
        toolCalls: [
          ToolCall(name: ToolName(step.toolName), arguments: step.arguments),
        ],
        taskId: request.taskId,
      );
      world.events.writer<ActorGenerateResponse>().send(response);
      return response;
    }
    // All actions spent; nothing left to decide. (In the plan-driven arm the
    // frontier policy normally terminates the loop before this is reached.)
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'done'},
      rawOutput: 'done',
      taskId: request.taskId,
    );
  }
}

Future<void> main(List<String> args) async {
  final filter = args.isEmpty ? '' : args.first;
  final tasks = loadTasks('benchmark/coding_suite/tasks')
      .where((t) => t.id.contains(filter))
      .toList();
  stdout.writeln('ADR 0009 falsifying experiment — ${tasks.length} tasks\n');

  // Both arms: same stateful handler (one action per call), same fixtures,
  // same checkers, Goal+step entities present in both. The ONLY variable is
  // the decision flow — continuation-after-every-result vs mechanical
  // frontier verification. (An earlier draft used the stateless
  // ScriptedSuiteHandler for the baseline; it re-emits all steps on every
  // continuation round until maxToolRounds exhausts — 17 "calls" for a
  // one-write task — which measures the handler, not the harness.)
  final baseline = <PlanRow>[];
  final planRows = <PlanRow>[];
  for (final task in tasks) {
    baseline.add(
      await runPlanArm(
        task,
        planFrontier: false,
        buildHandler: (t) => OneActionPerCallHandler(taskId: t.id),
      ),
    );
    planRows.add(
      await runPlanArm(
        task,
        planFrontier: true,
        buildHandler: (t) => OneActionPerCallHandler(taskId: t.id),
      ),
    );
  }

  // Comparison table.
  final b = StringBuffer()
    ..writeln('| task | base calls | plan calls | base tokens | plan tokens |'
        ' token Δ | mech verifies | pass |')
    ..writeln('|---|---|---|---|---|---|---|---|');
  var baseTok = 0, planTok = 0, baseCalls = 0, planCalls = 0;
  var allPass = true;
  for (var i = 0; i < tasks.length; i++) {
    final br = baseline[i];
    final pr = planRows[i];
    allPass &= pr.passed && br.passed;
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
      '| ${pr.mechanicalVerifications} '
      '| ${(br.passed && pr.passed) ? '✅' : '❌'} |',
    );
  }
  b..writeln('')
    ..writeln('**Totals** — calls: $baseCalls → $planCalls '
        '(${((planCalls - baseCalls) / (baseCalls == 0 ? 1 : baseCalls) * 100).toStringAsFixed(0)}%), '
        'tokens: $baseTok → $planTok '
        '(${((planTok - baseTok) / (baseTok == 0 ? 1 : baseTok) * 100).toStringAsFixed(0)}%)')
    ..writeln()
    ..writeln(allPass
        ? 'Both arms pass all checkers — comparison is valid.'
        : '⚠️ some tasks failed — comparison invalid, fix before reading deltas.');

  stdout.writeln(b);
  exit(0);
}
