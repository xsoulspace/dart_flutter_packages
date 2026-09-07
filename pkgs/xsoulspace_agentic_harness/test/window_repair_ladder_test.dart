// ignore_for_file: lines_longer_than_80_chars

/// ADR 0033 §3 — the mechanical repair ladder, LLM-free.
///
/// The wave-gate failure class, reproduced mechanically: a window-class
/// backend rejection (`context_window_exceeded`) used to re-enter the SAME
/// cut as a "Retry with tighter context" prompt — a prompt-shaped wish, no
/// mechanism — burning the attempt budget ~20× (afm_wave_md_run1.log). The
/// ladder: window-class failures DROP the decision with a named outcome
/// beat; transient failures keep the capped retry.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

/// A handler that always fails with the given error code — the minimal
/// window-overflow twin (the AFM pre-flight bounces the request NAMED).
class FailingGenerationHandler implements GenerationHandler {
  FailingGenerationHandler(this.error);

  final String error;
  int calls = 0;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    calls++;
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {},
      rawOutput: '',
      error: error,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

Future<World> _worldWithDecision(GenerationHandler handler) async {
  final world = await buildTestWorld(handler: handler);
  final scene = spawnScene(world);
  spawnActor(world, scene, openDecisionPrompt: 'edit the docs');
  syncScheduleExecutionFrame(world, explicitFrameId: 1);
  world.runSchedule(Schedules.agencyGrant);
  world.flush();
  world.runSchedule(Schedules.project);
  world.flush();
  await world.runScheduleAsync(Schedules.actorAct);
  world.flush();
  await Future<void>.delayed(const Duration(milliseconds: 50));
  world.runSchedule(Schedules.processResponses);
  world.flush();
  return world;
}

void main() {
  test(
    'window-class failure DROPS the decision — no same-cut retry, named '
    'outcome beat',
    () async {
      final handler = FailingGenerationHandler('context_window_exceeded');
      final world = await _worldWithDecision(handler);

      // Exactly ONE attempt — the futile round was never re-dispatched.
      expect(handler.calls, 1);
      // The decision is gone (dropped, not retried).
      expect(world.query2<Actor, OpenDecision>().toList(), isEmpty);
      // The named outcome beat is on the actor's thread — the host ladder
      // (converged profile / ready-move tier / escalate) reads THIS.
      final drops = beatsWithText(world, 'decision_dropped: '
          'context_window_exceeded');
      expect(drops, isNotEmpty);
      final beat = world.getEntity(drops.first).$1;
      expect(beat.get<BeatModality>()?.value, BeatModalityEnum.observation);
      expect(
        world.getResource<FacetIndex>().beatsFor(const ['decision_dropped']),
        isNotEmpty,
        reason: 'the outcome is indexed — the next cut can ray-trace it',
      );
      expectIdle(world);
    },
  );

  test('transient failure keeps the capped retry (unchanged behavior)', () async {
    final handler = FailingGenerationHandler('backend_failed');
    final world = await _worldWithDecision(handler);

    // One attempt so far; the decision re-opened with the retry prompt.
    expect(handler.calls, 1);
    final decisions = world.query2<Actor, OpenDecision>().toList();
    expect(decisions, hasLength(1));
    final (we, _, decision) = decisions.first;
    expect(decision.prompt, contains('Retry with tighter context'));
    expect(we.get<RetryCount>()?.value, 1);
  });

  test('isWindowClassFailure matches the named pre-flight and bridge codes',
      () {
    expect(isWindowClassFailure('context_window_exceeded'), isTrue);
    expect(
      isWindowClassFailure(
        'estimated 3200 tokens > 3800 budget — shrink the cut '
        '(composition/zoom) before calling AFM',
      ),
      isFalse,
      reason: 'the pre-flight message text alone is not the code',
    );
    expect(isWindowClassFailure('backend_failed'), isFalse);
    expect(isWindowClassFailure('generation_error'), isFalse);
  });
}
