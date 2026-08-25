// ignore_for_file: lines_longer_than_80_chars

/// Failure-path guarantees for the agent harness.
///
/// A failing tool, a missing handler, or a crashed handler must never dangle
/// an actor in `AwaitingResponse` — otherwise `HarnessLoop.canSleep()` is
/// never true and the harness hangs forever.

import 'dart:async';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/schedules.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

Future<(World, Entity)> _worldWithDecision({GenerationHandler? handler}) async {
  final world = await buildTestWorld(handler: handler);
  world.getResource<AgencyPolicy>().taskTimeout = const Duration(
    milliseconds: 100,
  );
  final scene = spawnScene(world);
  final actor = spawnActor(world, scene, openDecisionPrompt: 'go');
  world.flush();
  return (world, actor);
}

/// Drive one full cinematic cycle.
Future<void> _cycle(World world) =>
    runCycle(world, settleDelay: const Duration(milliseconds: 200));

void main() {
  group('tool failure guarantees', () {
    test('a throwing tool emits an error result and frees the actor', () async {
      final registry = ToolRegistry();
      registry.register(
        ToolDef(
          name: const ToolName('boom'),
          description: 'Always throws',
          execute: (args) async => throw StateError('boom'),
        ),
      );
      final handler = MockGenerationHandler(
        responseText: '',
        toolCalls: [const ToolCall(name: ToolName('boom'), arguments: {})],
      );
      final (world, actor) = await _worldWithDecision(handler: handler);
      world.getResource<ToolRegistryResource>().register('default', registry);
      world.upsertComponent(actor, const ActorTools(registryName: 'default'));
      world.flush();

      await _cycle(world);
      // Drain the async tool completion into a durable beat.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      world.runSchedule(Schedules.mechanical);
      world.flush();

      // The actor was freed despite the tool throwing.
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);
      expect(world.getResource<TaskRegistryResource>().isEmpty, isTrue);
      // The error landed as a tool-result beat.
      expect(beatsWithText(world, 'error').length, greaterThanOrEqualTo(1));
    });

    test('a hanging tool times out and frees the actor', () async {
      final registry = ToolRegistry();
      registry.register(
        ToolDef(
          name: const ToolName('hang'),
          description: 'Never completes',
          execute: (args) => Completer<String>().future,
        ),
      );
      final handler = MockGenerationHandler(
        responseText: '',
        toolCalls: [const ToolCall(name: ToolName('hang'), arguments: {})],
      );
      final (world, actor) = await _worldWithDecision(handler: handler);
      world.getResource<ToolRegistryResource>().register('default', registry);
      world.upsertComponent(actor, const ActorTools(registryName: 'default'));
      world.flush();

      await _cycle(world);
      // Let the 100ms taskTimeout sweep the hung tool, then persist the
      // timeout result as a beat.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      world.runSchedule(Schedules.mechanical);
      world.flush();

      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);
      expect(world.getResource<TaskRegistryResource>().isEmpty, isTrue);
    });
  });

  group('handler failure guarantees', () {
    test('a missing handler fails fast and frees the actor', () async {
      // No handler registered at all.
      final (world, actor) = await _worldWithDecision();

      await _cycle(world);

      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);
      expect(world.getEntity(actor).$1.has<Agency>(), isFalse);
      expect(world.getResource<TaskRegistryResource>().isEmpty, isTrue);
    });

    test('a throwing handler produces an error response and retries', () async {
      final (world, actor) = await _worldWithDecision(
        handler: ThrowingGenerationHandler(),
      );

      await _cycle(world);

      // Freed from this cycle...
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);
      expect(world.getResource<TaskRegistryResource>().isEmpty, isTrue);
      // ...and a retry decision was created (retry budget not exhausted).
      expect(world.getEntity(actor).$1.has<OpenDecision>(), isTrue);
      expect(world.getEntity(actor).$1.get<RetryCount>()?.value, 1);
    });

    test('a hung handler times out via taskTimeout', () async {
      final (world, actor) = await _worldWithDecision(
        handler: SilentGenerationHandler(),
      );

      // First dispatch; the handler hangs.
      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      world.runSchedule(Schedules.project);
      world.flush();
      await world.runScheduleAsync(Schedules.actorAct);
      world.flush();

      // The actor is awaiting with a registered task.
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isTrue);
      expect(world.getResource<TaskRegistryResource>().isEmpty, isFalse);

      // After the timeout elapses, the sweeper fails the task and the retry
      // path frees the actor.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      world.runSchedule(Schedules.processResponses);
      world.flush();

      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);
      expect(world.getResource<TaskRegistryResource>().isEmpty, isTrue);
      // A retry decision was created (retry budget not exhausted).
      expect(world.getEntity(actor).$1.has<OpenDecision>(), isTrue);
    });
  });

  group('id uniqueness', () {
    test('burst-created ids never collide', () {
      final ids = <String>{};
      for (var i = 0; i < 1000; i++) {
        ids
          ..add(TaskId.create().value)
          ..add(AgentId.create().value)
          ..add(ModelId.create().value);
      }
      expect(ids.length, 3000);
    });
  });
}
