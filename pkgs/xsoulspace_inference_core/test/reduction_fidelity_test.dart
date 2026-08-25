// ignore_for_file: lines_longer_than_80_chars

/// A3 reduction fidelity (Phase 4b): keyword-drift recall measures
/// *execution-context* quality for steps — plan discovery uses explicit
/// GoalLink/DependsOnStep links and is drift-free by construction. Reduced
/// beats must still trigger correct rays and causally gate scripted success.
///
/// Both scenarios are fully scripted (no LLM): projection, facet rays, and
/// mechanical verification are pure graph logic per the North Star.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

/// The evidence needle a scripted workspace predicate looks for.
const _evidenceNeedle = 'sha256 cafe';

void main() {
  group('A3 — execution-context keyword recall for steps', () {
    test(
      'reduced beats still trigger correct rays after mechanical verification',
      () async {
        final handler = ScriptedGenerationHandler([
          const ScriptedTurn(text: 'lru eviction swept cold entries'),
        ]);
        final world = await buildTestWorld(handler: handler);
        // Tight enough that the oversized decoy cannot fit; generous enough
        // that every execution-context beat does.
        world.upsertResource(ProjectionBudget(tokens: 150));
        world.flush();

        final scene = spawnScene(world);
        final actor = spawnActor(
          world,
          scene,
          systemPrompt: 'cache tuning agent',
          openDecisionPrompt: 'diagnose lru eviction thrash',
        );
        final thread = spawnThread(world, actor, scene);
        world.upsertComponent(actor, ActorThreads(threads: [thread]));

        // Plan discovery is link-based: goal → step chain via explicit links.
        final goal = world.spawnComponents([Goal(text: 'stabilize cache')]);
        final dependency = world.spawnComponents([
          Step(
            claim: 'profile hit rate',
            verificationKind: StepVerificationKind.mechanical,
            status: StepLifecycle.verified,
          ),
        ]);
        final frontier = world.spawnComponents([
          GoalLink(goal),
          DependsOnStep([dependency]),
          Step(
            claim: 'widen lru eviction window',
            verificationKind: StepVerificationKind.mechanical,
          ),
        ]);
        final executing = world.spawnComponents([
          GoalLink(goal),
          Step(
            claim: 'record eviction sweep results',
            verificationKind: StepVerificationKind.mechanical,
            criterionArgs: const {'artifact': 'cafe'},
          ),
        ]);
        world.flush();

        // Execution-context evidence + a decoy that must be pruned.
        final evidenceBeat = addIndexedBeat(
          world,
          thread,
          actor,
          'telemetry: lru thrash, artifact $_evidenceNeedle confirmed',
          ['lru', 'eviction'],
        );
        addIndexedBeat(world, thread, actor, 'museum ' * 200, ['museum']);

        // Mechanical workspace predicate over graph evidence — the same
        // contract seam-3 verifier tools follow.
        Future<Object?> verify(Object? args) async {
          final found = beatsWithText(world, _evidenceNeedle).isNotEmpty;
          return <String, dynamic>{
            'passed': found,
            'failures': found
                ? ''
                : 'artifact $_evidenceNeedle missing from workspace evidence',
          };
        }

        world.upsertResource(
          ToolExecutorResource()
            ..register(const ToolName('verify_step'), verify),
        );
        world.getResource<ToolRegistryResource>().register(
          'default',
          ToolRegistry(),
        );
        world.upsertComponent(actor, const ActorTools(registryName: 'default'));
        world.flush();

        // Cycle 1: scripted decision produces an observation beat carrying
        // fresh execution-context keywords.
        await runCycle(world);
        final responseBeat = beatsWithText(world, 'swept cold entries').single;
        expect(
          world.getResource<FacetIndex>().keywordsFor(responseBeat),
          containsAll(['lru', 'eviction']),
        );

        // Run mechanical step verification for the executing step; the
        // plan-frontier step stays open and in-frame.
        await _armContinuationMarker(world, actor);
        expect(
          await _verifyFrontierStep(world, actor: actor, step: executing),
          StepLifecycle.verified,
          reason: 'evidence beat gates the acceptance predicate',
        );
        expect(
          world.getEntity(frontier).$1.get<Step>()!.status,
          StepLifecycle.open,
          reason: 'verifying the executing step leaves the frontier untouched',
        );

        // The NEXT cut: a follow-up decision must ray-trace the reduced
        // execution-context beats — seeded evidence AND the scripted
        // observation — while the budget prunes only the decoy.
        world.upsertComponent(
          actor,
          const OpenDecision(prompt: 'confirm lru eviction fix'),
        );
        world.flush();
        projectFor(world);

        final index = world.getResource<FacetIndex>();
        final rays = index.beatsFor(keywordsOf('confirm lru eviction fix'));
        expect(
          rays,
          containsAll([evidenceBeat, responseBeat]),
          reason: 'reduced beats still trigger correct facet rays',
        );

        final situation = world.getEntity(actor).$1.get<Situation>()!;
        final projected = [
          for (final beat in situation.projectedBeats)
            fragmentText(world, beat),
        ].join('\n');
        expect(projected, contains('lru thrash'));
        expect(projected, contains('swept cold entries'));
        expect(
          projected.contains('museum'),
          isFalse,
          reason: 'decoy beat is pruned, not projected',
        );
        expect(situation.truncated, isTrue);
        expect(situation.explicitAbsences, isNotEmpty);
        expect(situation.tokensUsed, lessThanOrEqualTo(situation.tokenBudget));

        // Plan discovery stayed drift-free: explicit links project exactly
        // the open frontier step (verified dependency leaves the frontier).
        expect(situation.planSteps, ['widen lru eviction window']);

        _drainProjectionState(world, actor);
        expectIdle(world);
      },
    );
  });

  group('A3 — causal gating of scripted success', () {
    test('step verifies only when its evidence beat exists', () async {
      final world = await _gatedWorld(seedEvidence: true);
      final (:actor, :step) = _gatedHandles(world);

      expect(
        await _verifyFrontierStep(world, actor: actor, step: step),
        StepLifecycle.verified,
        reason: 'workspace predicate passes on real graph evidence',
      );
      _drainProjectionState(world, actor);
      expectIdle(world);
    });

    test(
      'fresh world without the evidence beat fails the same criterion',
      () async {
        final world = await _gatedWorld(seedEvidence: false);
        final (:actor, :step) = _gatedHandles(world);

        expect(
          await _verifyFrontierStep(world, actor: actor, step: step),
          StepLifecycle.failed,
          reason:
              'no evidence → no verification success; status flips to failed',
        );
        // The failure teaches instead of throwing.
        final executor = world.getResource<ToolExecutorResource>().get(
          const ToolName('verify_step'),
        )!;
        final out = await executor(const {'artifact': 'cafe'});
        expect(out, isA<Map>());
        expect((out! as Map)['passed'], isFalse);
        expect(
          (out as Map)['failures'],
          contains('missing from workspace evidence'),
        );
        _drainProjectionState(world, actor);
        expectIdle(world);
      },
    );
  });
}

/// Build a causal-gating world whose `verify_step` predicate reads the graph
/// for [_evidenceNeedle] — scripted success criteria flip ONLY on evidence.
Future<World> _gatedWorld({required bool seedEvidence}) async {
  final world = await buildTestWorld();
  Future<Object?> verify(Object? args) async {
    final found = beatsWithText(world, _evidenceNeedle).isNotEmpty;
    return <String, dynamic>{
      'passed': found,
      'failures': found
          ? ''
          : 'artifact $_evidenceNeedle missing from workspace evidence',
    };
  }

  world.upsertResource(
    ToolExecutorResource()..register(const ToolName('verify_step'), verify),
  );
  world.getResource<ToolRegistryResource>().register('default', ToolRegistry());
  final scene = spawnScene(world);
  final actor = spawnActor(world, scene);
  world.upsertComponent(actor, const ActorTools(registryName: 'default'));
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  if (seedEvidence) {
    addIndexedBeat(
      world,
      thread,
      actor,
      'build log: artifact $_evidenceNeedle validated',
      ['artifact', 'sha256'],
    );
  }
  world.spawnComponents([
    Step(
      claim: 'publish signed artifact',
      verificationKind: StepVerificationKind.mechanical,
      criterionArgs: const {'artifact': 'cafe'},
    ),
  ]);
  world.flush();

  await _armContinuationMarker(world, actor);
  return world;
}

/// Land one tool result while [actor] is decision-free so
/// `processToolResultsSystem` arms the ReAct continuation marker — the
/// window `verifyStepSystem` needs to run a step's acceptance predicate.
Future<void> _armContinuationMarker(World world, Entity actor) async {
  final taskId = TaskId.create();
  world.getResource<TaskRegistryResource>().register(taskId, TaskHandle());
  world.events.writer<ToolCallEvent>().send(
    ToolCallEvent(
      actorEntity: actor,
      call: const ToolCall(name: ToolName('run_probe'), arguments: {}),
      taskId: taskId,
    ),
  );
  world.runSchedule(Schedules.mechanical);
  world.flush();
  // Let the async tool closure complete and the second mechanical pass turn
  // the result event into a beat + marker.
  await Future<void>.delayed(const Duration(milliseconds: 30));
  world.runSchedule(Schedules.mechanical);
  world.flush();
}

({Entity actor, Entity step}) _gatedHandles(World world) => (
  actor: world.query2<Actor, ActorThreads>().single.$1.entity,
  step: world.query<Step>().single.$1.entity,
);

/// Open the plan-linked decision inside the marker window and run the
/// mechanical schedule so `verifyStepSystem` executes the acceptance
/// predicate. Returns the step's resulting lifecycle.
Future<StepLifecycle> _verifyFrontierStep(
  World world, {
  required Entity actor,
  required Entity step,
}) async {
  expect(
    world.getEntity(actor).$1.has<ToolResultPendingMarker>(),
    isTrue,
    reason: 'landed tool result must arm the continuation marker',
  );
  world.upsertComponent(
    actor,
    OpenDecision(prompt: 'close out the step', stepId: step),
  );
  world.flush();
  world.runSchedule(Schedules.mechanical);
  await Future<void>.delayed(Duration.zero);
  world.flush();
  return world.getEntity(step).$1.get<Step>()!.status;
}

/// Remove test-injected decision/marker state so [expectIdle] reflects only
/// harness-owned work.
void _drainProjectionState(World world, Entity actor) {
  final entity = world.getEntity(actor).$1;
  if (entity.has<OpenDecision>()) entity.remove<OpenDecision>();
  if (entity.has<Agency>()) entity.remove<Agency>();
  if (entity.has<ToolResultPendingMarker>()) {
    entity.remove<ToolResultPendingMarker>();
  }
  if (entity.has<Situation>()) entity.remove<Situation>();
  world.flush();
}
