// ignore_for_file: lines_longer_than_80_chars

/// J8.1 — the exhausted-attempt pump, DRIVER-level gate (LLM-free).
///
/// The measured on-device defect (afm_wave trusted run, 2026-09-08): after
/// the goal-attempt budget exhausted, the react-continuation pump kept
/// re-sending the identical "attempt N/3" prompt (Σ26 re-opens, ~2 min
/// wall, ~10k tokens) instead of ending the decision. The pump's fuel was
/// the STALE failed [GoalVerified] (re-firing the repair policy on every
/// tool-result marker) plus the driver's own counter clobbering the
/// monotonic [AttemptCount]. This gate pins the fixed behavior end-to-end
/// through the SAME driver the AFM wave rows use:
///
/// - one failed verification re-prompts EXACTLY ONCE (the policy consumes
///   the verdict — see exactly_one_resend_test.dart in the harness pkg);
/// - after [GoalAttemptsExhausted] the driver loop BREAKS (J8 rung 1) —
///   no repair prompt is ever re-sent on an exhausted actor;
/// - the [AttemptCount] component is the ONE budget truth (the driver
///   reads it, never overwrites it).
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show CheckerSpec;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

/// A permanently failing handler that CAPTURES every decision prompt it is
/// handed — the re-send ledger the gate asserts against.
class _CountingFailingHandler implements GenerationHandler {
  final prompts = <String>[];

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    prompts.add(request.prompt);
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'writing a broken program'},
      rawOutput: 'writing a broken program',
      toolCalls: const [
        ToolCall(
          name: ToolName('write'),
          arguments: {'path': 'main.dart', 'content': 'void main() => throw 1;'},
        ),
      ],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

void main() {
  test('J8.1 pump gate: one re-send per failed verification, then END '
      '(no identical repair prompt is ever re-sent)', () async {
    final jail = await Directory.systemTemp.createTemp('pump_gate_');
    addTearDown(() => jail.delete(recursive: true).catchError((_) {}));
    final handler = _CountingFailingHandler();
    final task = CodingAgentTask(
      id: 'pump_gate',
      prompt: 'make a program',
      checkers: [CheckerSpec(type: 'runs', path: 'main.dart')],
      runCommand: ['dart', 'run', 'main.dart'],
    );
    final sw = Stopwatch()..start();
    final r = await runCodingAgentOnce(
      task: task,
      jail: jail,
      handler: handler,
      backend: 'scripted_llm_free',
      maxGoalAttempts: 3,
    );
    sw.stop();

    expect(r.passed, isFalse);
    expect(formatRunLog(r), contains('goal_unverifiable'),
        reason: 'the budget exhausts (the terminal record still ships)');
    expect(sw.elapsed, lessThan(const Duration(minutes: 2)));

    // THE PUMP SIGNATURE (was Σ26 identical re-opens on-device): the SAME
    // repair prompt text appearing more than once. After the fix, every
    // failed verification re-prompts EXACTLY ONCE — every repair prompt
    // is distinct, and re-sends track failed verifications 1:1.
    final repairPrompts = handler.prompts
        .where((p) =>
            p.contains('Goal not verified by running code') ||
            p.contains('Your previous attempt did not satisfy verification'))
        .toList();
    final duplicates = <String, int>{};
    for (final p in repairPrompts) {
      duplicates.update(p, (v) => v + 1, ifAbsent: () => 1);
    }
    expect(
      [for (final e in duplicates.entries) if (e.value > 1) e.key],
      isEmpty,
      reason: 'J8.1: no repair prompt may repeat — the pump is dead. '
          'Got: $duplicates',
    );
    // Re-sends track failed verifications: each is numbered, and the
    // numbers strictly advance (the monotonic counter is the one truth).
    final attemptNumbers = [
      for (final p in repairPrompts)
        RegExp(r'attempt (\d+)/').firstMatch(p)?.group(1),
    ].nonNulls.toList();
    expect(attemptNumbers.toSet().length, attemptNumbers.length,
        reason: 'attempt numbers never repeat: $attemptNumbers');
    // The whole failing run stays MECHANICALLY bounded: one ReAct chain
    // (maxToolRounds=12 — continuations are the designed carrier between
    // verify stamps) + one re-send per failed verification (3). The
    // measured pump burned 26+ IDENTICAL re-opens on top of this bound.
    expect(r.decisions, lessThanOrEqualTo(15),
        reason: 'the failing run ends on exhaustion, not on re-sends '
            '(decisions: ${r.decisions}, prompts: ${handler.prompts.length})');
  });
}
