// ignore_for_file: lines_longer_than_80_chars

/// J8.1 — the exhausted-attempt pump gate (LLM-free, deterministic).
///
/// The measured defect (afm_wave trusted run, 2026-09-08): the stale failed
/// [GoalVerified] re-fired the repair policy on EVERY tool-result marker —
/// Σ26 identical "attempt N/3" re-opens, ~2 min wall, ~10k tokens in ONE
/// run — instead of ending the decision. The law that now holds:
///
/// - **One failed verification re-prompts EXACTLY ONCE** — the policy
///   CONSUMES the verdict; the next verifier stamp gates the next re-send.
/// - **A continuation never outlives the budget** — after
///   [GoalAttemptsExhausted] the decision chain ENDS (J8 rung 1); the
///   overseer window is the designated post-exhaustion path.
/// - The monotonic [AttemptCount] is the ONE budget truth — the driver
///   reads it, never clobbers it (host-side, gated in
///   coding_agent_scripted_test.dart).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/decisions/decision_flow.dart';
import 'package:xsoulspace_agentic_harness/src/systems/decision_flow_system.dart'
    show ToolResultPendingMarker;
import 'package:xsoulspace_agentic_harness/src/tooling/build_gates.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

(World, Entity, Entity) _goalActor(World world) {
  final scene = spawnScene(world);
  final actor = spawnActor(world, scene);
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  world.flush();
  return (world, actor, thread);
}

void main() {
  group('J8.1 — one failed verification re-prompts EXACTLY ONCE', () {
    test('the verdict is CONSUMED by the re-send — the same stale verdict '
        'can never re-prompt twice', () async {
      final world = await buildTestWorld(decisionFlow: defaultGoalFlow());
      registerExperimentComponents(world);
      final (world_, actor, _) = _goalActor(world);
      final we = world_.getEntity(actor).$1;
      we.insert(GoalVerified(passed: false, detail: 'exit=1'));
      we.insert(const ToolResultPendingMarker());
      world.flush();

      var ctx = DecisionContext(actor: actor, world: world_, tick: 1);
      final first = const RunGradedGoalPolicy().evaluate(ctx);
      expect(first, isNotNull, reason: 'one re-send per failed verification');
      world.flush();

      // The verdict is CONSUMED: a second evaluation on the SAME stale
      // verdict (the pump — the tool result is still the latest) abstains.
      ctx = DecisionContext(actor: actor, world: world_, tick: 2);
      expect(we.get<GoalVerified>(), isNull,
          reason: 'J8.1: the policy consumes the verdict it re-sends on');
      expect(const RunGradedGoalPolicy().evaluate(ctx), isNull,
          reason: 'the SAME failed verdict re-prompts EXACTLY ONCE');
      expectIdle(world);
    });

    test('re-sends track failed verifications 1:1 — the counter never '
        'burns on markers between verify stamps', () async {
      final world = await buildTestWorld(decisionFlow: defaultGoalFlow());
      registerExperimentComponents(world);
      final (world_, actor, _) = _goalActor(world);
      final we = world_.getEntity(actor).$1;

      // Verification #1 fails → exactly one re-send.
      we.insert(GoalVerified(passed: false, detail: 'exit=1'));
      world.flush();
      var ctx = DecisionContext(actor: actor, world: world_, tick: 1);
      expect(const RunGradedGoalPolicy().evaluate(ctx), isNotNull);
      world.flush();
      expect(we.get<AttemptCount>()?.value, 1);

      // Three tool-result markers arrive with NO new verification stamp
      // (the pump's fuel — intermediate results between verify stamps):
      // every one abstains. The counter stays at 1.
      we.insert(const ToolResultPendingMarker());
      for (var tick = 2; tick <= 4; tick++) {
        ctx = DecisionContext(actor: actor, world: world_, tick: tick);
        expect(const RunGradedGoalPolicy().evaluate(ctx), isNull,
            reason: 'no fresh verdict → no re-send (the pump is dead)');
      }
      expect(we.get<AttemptCount>()?.value, 1);

      // Verification #2 fails → exactly one more re-send (2/3).
      we
        ..insert(GoalVerified(passed: false, detail: 'exit=1 again'))
        ..insert(const ToolResultPendingMarker());
      world.flush();
      ctx = DecisionContext(actor: actor, world: world_, tick: 5);
      final second = const RunGradedGoalPolicy().evaluate(ctx);
      expect(second, isNotNull);
      expect(second!.prompt, contains('attempt 2/'));
      expectIdle(world);
    });

    test('exhaustion ends the chain: the final failed verification stamps '
        'exhaustion, consumes the verdict, and suspends the thread',
        () async {
      final world = await buildTestWorld(decisionFlow: defaultGoalFlow());
      registerExperimentComponents(world);
      final (world_, actor, thread) = _goalActor(world);
      final we = world_.getEntity(actor).$1;

      // Two verifications already consumed (attempts 1, 2). The THIRD
      // failed verification exhausts the default budget (3).
      we
        ..insert(AttemptCount(2))
        ..insert(GoalVerified(passed: false, detail: 'exit=1'));
      world.flush();
      final ctx = DecisionContext(actor: actor, world: world_, tick: 1);
      expect(const RunGradedGoalPolicy().evaluate(ctx), isNull);
      world.flush();
      expect(we.get<GoalAttemptsExhausted>()?.reason, contains('3 failed'));
      expect(we.get<GoalVerified>(), isNull,
          reason: 'no stale verdict may outlive exhaustion');
      expect(
        world_.getEntity(thread).$1.get<ThreadStatus>()?.value,
        ThreadStatusEnum.suspended,
      );
      expectIdle(world);
    });
  });

  group('J8.1 — a continuation never outlives the attempt budget', () {
    test('ReActContinuationPolicy abstains after GoalAttemptsExhausted',
        () async {
      final world = await buildTestWorld(decisionFlow: defaultGoalFlow());
      registerExperimentComponents(world);
      final (world_, actor, _) = _goalActor(world);
      final we = world_.getEntity(actor).$1;
      we
        ..insert(const GoalAttemptsExhausted('goal_unverifiable: 3 failed'))
        ..insert(const ToolResultPendingMarker());
      world.flush();
      var ctx = DecisionContext(actor: actor, world: world_, tick: 1);
      expect(ReActContinuationPolicy().evaluate(ctx), isNull,
          reason: 'J8 rung 1: after exhaustion the decision chain ENDS — '
              'the overseer window is the post-exhaustion path');
      // The same world WITHOUT exhaustion still continues (the gate is
      // surgical — it must not neuter the healthy continuation path).
      we.remove<GoalAttemptsExhausted>();
      world.flush();
      ctx = DecisionContext(actor: actor, world: world_, tick: 2);
      expect(ReActContinuationPolicy().evaluate(ctx), isNotNull);
      expectIdle(world);
    });
  });
}
