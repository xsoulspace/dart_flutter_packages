// ignore_for_file: lines_longer_than_80_chars

/// STEP CLAIMING over the shared plan frontier — worker-gradient rung 2
/// (ADR 0009 §"Planning is projection" + Amendment §3).
///
/// Gates:
/// - open step + verified deps + no claimant → claimable by a REGISTERED
///   topology actor (`claimStep`);
/// - a SECOND claim BOUNCES LOUDLY: named reason `step_already_claimed`
///   carrying the CURRENT claimant — never a silent merge (the strict form
///   throws, so a caller cannot ignore contention);
/// - the frontier PROJECTS claim state: `claimedBy` + `claimable` on every
///   row, token-budgeted exactly as before (claim fields cost no tokens);
/// - coordination needs NO coordinator subsystem — claims + loud bounces
///   cover disjoint work; release/steal is a named NON-claim (not built).
library;

import 'package:ecsly/ecsly.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/agent.dart' show AgentPlugin;
import 'package:xsoulspace_agentic_harness/src/data_models/data_models.dart'
    show Goal, StepClaimant;
import 'package:xsoulspace_agentic_harness/src/decisions/actor_topology.dart';
import 'package:xsoulspace_agentic_harness/src/narrative/narrative.dart'
    show DependsOnStep, GoalLink, Step, StepLifecycle;
import 'package:xsoulspace_agentic_harness/src/systems/projection/projection_systems.dart'
    show PlanFrontierRow, projectPlanFrontier;

import 'support/agent_harness_support.dart';

World _world() => World()..addPlugin(AgentPlugin());

({Entity step, Entity otherStep, Entity actorA, Entity actorB})
_twoActorWorld(World world) {
  final actors = registerActorTopology(
    world,
    const ActorTopologySpec(
      worlds: ['main'],
      actors: [
        TopologyActorSpec(id: 'actor-a', role: 'model', tier: 'hosted'),
        TopologyActorSpec(id: 'actor-b', role: 'model', tier: 'afm'),
      ],
    ),
  );
  final goal = world.spawnComponents([Goal(text: 'ship the fix')]);
  final step = world.spawnComponents([
    Step(claim: 'replace the Usage section'),
    GoalLink(goal),
  ]);
  final otherStep = world.spawnComponents([
    Step(claim: 'set retry.max_attempts'),
    GoalLink(goal),
  ]);
  world.flush();
  return (
    step: step,
    otherStep: otherStep,
    actorA: actors[0],
    actorB: actors[1],
  );
}

void main() {
  group('step claiming (coordination = the shared plan frontier)', () {
    test('claim → frontier shows claimed-by; unclaimed row stays claimable',
        () {
      final world = _world();
      final w = _twoActorWorld(world);
      final claim = claimStep(world, w.step, w.actorA);
      expect(claim, isA<StepClaimed>());
      expect((claim as StepClaimed).actorId, 'actor-a');

      final projection = projectPlanFrontier(
        world,
        null,
        budget: 1000,
        estimator: (text) => (text.length / 4).ceil(),
      );
      final Map<Entity, PlanFrontierRow> rows = {
        for (final row in projection.rows) row.step: row,
      };
      final claimedRow = rows[w.step]!;
      final freeRow = rows[w.otherStep]!;
      expect(claimedRow.claimedBy, 'actor-a');
      expect(claimedRow.claimable, isFalse);
      expect(freeRow.claimedBy, isNull);
      expect(freeRow.claimable, isTrue);
      // The claim state projects as a green-screen absence for the others.
      expect(
        projection.explicitAbsences.join(' '),
        contains('claimed by another actor'),
      );
      // Token accounting unchanged: only claim text is budgeted.
      expect(projection.tokensUsed, greaterThan(0));
      expectIdle(world);
    });

    test('second claim BOUNCES LOUDLY carrying the current claimant', () {
      final world = _world();
      final w = _twoActorWorld(world);
      claimStep(world, w.step, w.actorA);

      final bounce = claimStep(world, w.step, w.actorB);
      expect(bounce, isA<StepClaimBounced>());
      final b = bounce as StepClaimBounced;
      expect(b.reason, 'step_already_claimed');
      expect(b.currentClaimantId, 'actor-a');

      // The strict form throws so a caller cannot ignore contention.
      expect(
        () => claimStepStrict(world, w.step, w.actorB),
        throwsA(
          isA<StepClaimBounce>()
              .having((e) => e.reason, 'reason', 'step_already_claimed')
              .having((e) => e.currentClaimantId, 'claimant', 'actor-a'),
        ),
      );

      // The claim did NOT merge or move: actor-a still holds it.
      final (facade, _) = world.getEntity(w.step);
      expect(
        claimantIdOf(world, facade.get<StepClaimant>()!.actor),
        'actor-a',
      );
      expectIdle(world);
    });

    test('claim requires an OPEN step with VERIFIED dependencies', () {
      final world = _world();
      final w = _twoActorWorld(world);
      final dependency = world.spawnComponents([Step(claim: 'dependency')]);
      final blocked = world.spawnComponents([
        Step(claim: 'blocked step'),
        DependsOnStep([dependency]),
      ]);
      world.flush();

      // The dependency is open, not verified → bounce, no claim lands.
      expect(
        (claimStep(world, blocked, w.actorA) as StepClaimBounced).reason,
        'dependencies_not_verified',
      );
      final (blockedFacade, _) = world.getEntity(blocked);
      expect(blockedFacade.get<StepClaimant>(), isNull);

      // Verify the dependency mechanically → the step becomes claimable.
      final (depFacade, _) = world.getEntity(dependency);
      depFacade.get<Step>()!.status = StepLifecycle.verified;
      world.flush();
      expect(isStepClaimable(world, blocked), isTrue);
      expect(claimStep(world, blocked, w.actorA), isA<StepClaimed>());
      expectIdle(world);
    });

    test('claim refuses non-open steps and unregistered actors', () {
      final world = _world();
      final w = _twoActorWorld(world);
      final done = world.spawnComponents([Step(claim: 'already done')]);
      final (doneFacade, _) = world.getEntity(done);
      doneFacade.get<Step>()!.status = StepLifecycle.verified;
      world.flush();
      expect(
        (claimStep(world, done, w.actorA) as StepClaimBounced).reason,
        'step_not_open:verified',
      );

      // A plain entity that never registered in the topology is refused —
      // claims come only from DECLARED graph data.
      final outsider = world.spawnComponents([Step(claim: 'not a claimant')]);
      expect(
        (claimStep(world, w.otherStep, outsider) as StepClaimBounced).reason,
        'actor_not_in_topology',
      );
      final (otherFacade, _) = world.getEntity(w.otherStep);
      expect(otherFacade.get<StepClaimant>(), isNull);
      expectIdle(world);
    });

    test('frontier rows stay token-budgeted as today (claim adds no tokens)',
        () {
      final world = _world();
      _twoActorWorld(world);
      final goal = world.spawnComponents([Goal(text: 'budget probe')]);
      world.spawnComponents([Step(claim: 'x' * 400), GoalLink(goal)]);
      world.flush();
      final projection = projectPlanFrontier(
        world,
        null,
        budget: 40,
        estimator: (text) => (text.length / 4).ceil(),
      );
      // The 400-char claim (100 tokens) cannot fit a 40-token budget; the
      // two short rows project and the long one is a named absence — the
      // budget law is exactly the pre-claim behavior.
      expect(projection.rows, hasLength(2));
      expect(projection.truncated, isTrue);
      expect(projection.explicitAbsences.join(' '), contains('off-screen'));
      expectIdle(world);
    });
  });
}
