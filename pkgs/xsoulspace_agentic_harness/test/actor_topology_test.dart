// ignore_for_file: lines_longer_than_80_chars

/// ACTOR TOPOLOGY AS DATA + the mechanical class — worker-gradient rung 2
/// (ADR 0009 Amendment §3; ADR 0031 §4: actors are declared data riding
/// above identity, never authority).
///
/// Gates:
/// - topology registration e2e: two actors (model + mechanical), one world
///   — actors land AS GRAPH DATA (`TopologyActor` entities), nothing loops;
/// - validation is named-and-loud: duplicate ids, empty fields, unknown
///   tool registry, a mechanical actor with a token budget — every
///   violation is a named error, never a silent fallback;
/// - the MECHANICAL CLASS works a consented ready step through the
///   topology DECLARATION (zero tokens, deny-by-default consent, outcome
///   recorded as step data — mechanical_actor.dart reused, not forked);
/// - an UNCONSENTED step is denied (named refusal) and stays open;
/// - an actor that does not declare `mechanical` (or is not registered at
///   all) is refused the mechanical path.
library;

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart' show ToolRegistry;
import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/agent.dart' show AgentPlugin;
import 'package:xsoulspace_agentic_harness/src/data_models/data_models.dart'
    show StepAction, StepStatus, TopologyActor;
import 'package:xsoulspace_agentic_harness/src/decisions/actor_topology.dart';
import 'package:xsoulspace_agentic_harness/src/narrative/narrative.dart'
    show Step, StepLifecycle, StepVerificationKind;
import 'package:xsoulspace_agentic_harness/src/resources/resources.dart'
    show ToolRegistryResource;
import 'package:xsoulspace_agentic_harness/src/tooling/mechanical_actor.dart';

import 'support/agent_harness_support.dart';

World _world() => World()..addPlugin(AgentPlugin());

ActorTopologySpec _spec({
  List<String> worlds = const ['main'],
  List<TopologyActorSpec> actors = const [
    TopologyActorSpec(
      id: 'model-a',
      role: 'model',
      tier: 'hosted',
      budget: 4000,
      toolRegistry: 'default',
    ),
    TopologyActorSpec(
      id: 'mech-1',
      role: 'mechanical',
      tier: 'mechanical',
      toolRegistry: 'default',
    ),
  ],
}) => ActorTopologySpec(worlds: worlds, actors: actors);

Entity _readyStep(World world, {String claim = 'replace the Usage section'}) =>
    world.spawnComponents([
      Step(
        claim: claim,
        verificationKind: StepVerificationKind.mechanical,
      ),
      StepAction('edit_symbol', {
        'action': 'replace_section',
        'symbolId': 'sec_1',
        'body': 'new body',
      }),
      StepStatus('open'),
    ]);

void main() {
  group('topology registration (spawn = actor registration in the world)', () {
    test('registers two actors into one world as graph data', () {
      final world = _world()
        ..upsertResource(ToolRegistryResource()..register('default', ToolRegistry()));
      final entities = registerActorTopology(world, _spec());
      expect(entities, hasLength(2));
      final actors = [
        for (final e in entities) world.getEntity(e).$1.get<TopologyActor>()!,
      ];
      expect(actors[0].id, 'model-a');
      expect(actors[0].role, 'model');
      expect(actors[0].tier, 'hosted');
      expect(actors[0].budget, 4000);
      expect(actors[0].toolRegistry, 'default');
      expect(actors[1].id, 'mech-1');
      expect(actors[1].role, 'mechanical');
      expect(actors[1].tier, 'mechanical');
      expect(actors[1].budget, 0);
      expectIdle(world);
    });

    test('validation rejects violations with named errors (all reasons)', () {
      expect(
        validateTopologySpec(_spec(worlds: const [])),
        contains('empty_worlds'),
      );
      expect(
        validateTopologySpec(_spec(actors: const [])),
        contains('empty_actors'),
      );
      final dup = validateTopologySpec(
        _spec(
          actors: const [
            TopologyActorSpec(id: 'mech-1', role: 'mechanical', tier: 'mech'),
            TopologyActorSpec(id: 'mech-1', role: 'mechanical', tier: 'mech'),
          ],
        ),
      );
      expect(dup, contains('duplicate_actor_id:mech-1'));
      final mechanicalBudget = validateTopologySpec(
        _spec(
          actors: const [
            TopologyActorSpec(id: 'm', role: 'mechanical', tier: 'mech', budget: 10),
          ],
        ),
      );
      expect(mechanicalBudget, contains('mechanical_actor_with_token_budget:m'));
    });

    test('registration is LOUD on a world cross-check: unknown registry', () {
      final world = _world()..upsertResource(ToolRegistryResource());
      expect(
        () => registerActorTopology(
          world,
          _spec(
            actors: const [
              TopologyActorSpec(
                id: 'model-a',
                role: 'model',
                tier: 'hosted',
                budget: 100,
                toolRegistry: 'no-such-registry',
              ),
            ],
          ),
        ),
        throwsA(
          isA<TopologyValidationError>().having(
            (e) => e.errors,
            'errors',
            contains('unknown_tool_registry:model-a:no-such-registry'),
          ),
        ),
      );
      // A failed registration leaves NO partial topology behind.
      expect(
        world.prepareQuery1<TopologyActor>().entities.toList(),
        isEmpty,
      );
      expectIdle(world);
    });
  });

  group('the mechanical class works consented ready steps', () {
    test('declared mechanical actor works a consented ready step', () async {
      final world = _world();
      final topology = registerActorTopology(world, _spec());
      final mech = topology[1];
      final step = _readyStep(world);
      world.flush();

      final claim = claimStep(world, step, mech);
      expect(claim, isA<StepClaimed>());

      final out = await workClaimedReadyStep(
        world: world,
        stepEntity: step,
        actorEntity: mech,
        editExecutor: (args) async => {'ok': true, 'files': ['docs/README.md']},
        consent: (args) => true,
      );
      expect(out['ok'], isTrue);

      // The outcome is DATA on the step (one step, one execution).
      final (facade, _) = world.getEntity(step);
      expect(facade.get<Step>()!.status, StepLifecycle.verified);
      expect(facade.get<StepStatus>()!.value, 'verified');
      expect(facade.get<StepAction>()!.outcome?['ok'], isTrue);
      expectIdle(world);
    });

    test('unconsented step is DENIED (named) and stays open', () async {
      final world = _world();
      final mech = registerActorTopology(world, _spec())[1];
      final step = _readyStep(world);
      world.flush();
      claimStep(world, step, mech);

      final out = await workClaimedReadyStep(
        world: world,
        stepEntity: step,
        actorEntity: mech,
        editExecutor: (args) async => {'ok': true},
        consent: (args) => false,
      );
      expect(out['ok'], isFalse);
      expect(out['code'], 'mechanical_actor_unconsented');

      // Nothing executed → the step is NOT forged into `failed`; it stays
      // open and claimed (release/steal is a named non-claim).
      final (facade, _) = world.getEntity(step);
      expect(facade.get<Step>()!.status, StepLifecycle.open);
      expect(facade.get<StepAction>()!.outcome, isNull);
      expectIdle(world);
    });

    test('a non-mechanical or unregistered actor is refused', () async {
      final world = _world();
      final topology = registerActorTopology(world, _spec());
      final modelActor = topology[0];
      final step = _readyStep(world);
      world.flush();
      claimStep(world, step, modelActor);

      final refused = await workClaimedReadyStep(
        world: world,
        stepEntity: step,
        actorEntity: modelActor,
        editExecutor: (args) async => {'ok': true},
        consent: (args) => true,
      );
      expect(refused['ok'], isFalse);
      expect(refused['code'], 'mechanical_actor_not_declared');

      final unregistered = world.spawnComponents([StepStatus('open')]);
      final notRegistered = await workClaimedReadyStep(
        world: world,
        stepEntity: step,
        actorEntity: unregistered,
        editExecutor: (args) async => {'ok': true},
        consent: (args) => true,
      );
      expect(notRegistered['ok'], isFalse);
      expect(notRegistered['code'], 'mechanical_actor_not_registered');
      expectIdle(world);
    });
  });
}
