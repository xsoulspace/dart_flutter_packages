// ignore_for_file: lines_longer_than_80_chars

/// Regression: ADR 0002 — handler response contract.
///
/// A handler that ONLY returns its response (never sends to the event
/// channel) must not deadlock the actor. `actorActSystem` publishes the
/// returned response when the channel hasn't seen the taskId. A handler that
/// sends AND returns is unaffected — no double-send.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

/// Return-only handler: the natural way to write one, previously a silent
/// deadlock.
class _ReturnOnlyHandler implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'returned'},
      rawOutput: 'returned',
      taskId: request.taskId,
    );
  }
}

void main() {
  test('return-only handler does not deadlock; response lands once', () async {
    final world = await buildTestWorld(handler: _ReturnOnlyHandler());
    const modelId = ModelId('m');
    world.getResource<ModelRouterResource>().router.models[modelId] = Model(
      id: modelId,
      tier: 0,
    );
    final scene = spawnScene(world);
    spawnActor(world, scene, openDecisionPrompt: 'hello');
    world.flush();

    await HarnessLoop(world: world).runUntilIdle();

    // Exactly one channel send — the synthesized fallback, no duplicates.
    expect(world.events.stats<ActorGenerateResponse>().sent, 1);
    expectIdle(world);

    // The actor's answer became a beat.
    expect(beatsWithText(world, 'returned'), hasLength(1));
  });

  test('send-and-return handler still delivers exactly once', () async {
    final world = await buildTestWorld(
      handler: MockGenerationHandler(responseText: 'mocked'),
    );
    const modelId = ModelId('m');
    world.getResource<ModelRouterResource>().router.models[modelId] = Model(
      id: modelId,
      tier: 0,
    );
    final scene = spawnScene(world);
    spawnActor(world, scene, openDecisionPrompt: 'hello');
    world.flush();

    await HarnessLoop(world: world).runUntilIdle();

    // One send from the handler itself; no synthesized duplicate.
    expect(world.events.stats<ActorGenerateResponse>().sent, 1);
    expectIdle(world);
  });
}
