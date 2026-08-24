// ignore_for_file: lines_longer_than_80_chars

/// Proof of the idle-goal verification rule (ADR 0009 follow-up):
/// "actor idle + open goal ⇒ verify before sleep".
///
/// Deterministic scenario: a model that ANSWERS WITHOUT ACTING on its first
/// call, and only performs the edit when mechanically nudged with failing
/// criteria.
///
/// - Without the rule (pre-fix behavior): episode ends after 1 call, goal
///   unverified, task FAILS silently.
/// - With the rule: verifier detects failure while idle → one tight nudge →
///   model acts → criteria pass → terminate. 2 calls, PASS.
///
/// Run: `dart run benchmark/idle_verify_proof.dart`
library;

import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'coding_suite/scripted_handler.dart';
import 'coding_suite/task_spec.dart';
import 'plan_frontier_arms.dart';

/// Answers without acting on call #1; performs the real edit afterwards.
class FlakyAnswerFirstHandler implements GenerationHandler {
  FlakyAnswerFirstHandler({required this.taskId});
  final String taskId;
  var _callCount = 0;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    _callCount++;
    if (_callCount == 1) {
      // The failure mode observed on real AFM (edit_02): a confident
      // text-only answer, no tool call, nothing to verify against.
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: const {'text': 'Done! I renamed the constant.'},
        rawOutput: 'Done! I renamed the constant.',
        taskId: request.taskId,
      );
    }
    final steps = scriptedBehaviors[taskId]!;
    final idx = _callCount - 2;
    final ActorGenerateResponse response;
    if (idx >= 0 && idx < steps.length) {
      final step = steps[idx];
      response = ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: {'text': 'step $_callCount'},
        rawOutput: 'step $_callCount',
        toolCalls: [
          ToolCall(name: ToolName(step.toolName), arguments: step.arguments),
        ],
        taskId: request.taskId,
      );
    } else {
      // Steps exhausted.
      response = ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: const {'text': 'done'},
        rawOutput: 'done',
        taskId: request.taskId,
      );
    }
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

Future<void> main() async {
  final tasks = loadTasks('benchmark/coding_suite/tasks')
      .where((t) => t.id == 'edit_01_rename_constant')
      .toList();
  final row = await runPlanArm(
    tasks.first,
    planFrontier: true,
    buildHandler: (t) => FlakyAnswerFirstHandler(taskId: t.id),
  );

  stdout.writeln('calls=${row.llmCalls} passed=${row.passed} '
      'cumTokens=${row.cumulativeTokens}');
  final ok = row.passed && row.llmCalls == 2;
  stdout.writeln(ok
      ? '✅ idle-verify rule works: answer-without-acting was caught, '
          'nudged once, and the goal was achieved.'
      : '❌ rule did not behave as designed.');
  exit(ok ? 0 : 1);
}