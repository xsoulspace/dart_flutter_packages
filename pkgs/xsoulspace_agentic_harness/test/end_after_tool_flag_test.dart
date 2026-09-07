// ignore_for_file: lines_longer_than_80_chars

/// ADR 0033 §4 — the decision ends MECHANICALLY after the move: the
/// `end_after_tool` flag rides the inference request metadata when
/// [NativeLoopPolicy.endAfterFirstTool] is set, and is ABSENT otherwise
/// (default OFF — unchanged resume behavior everywhere until the on-device
/// wave row re-runs). The Swift side consumes the flag
/// (bridge/tests/BridgeTests.swift covers the resume/finish contract).
library;

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

/// A fake inference client that CAPTURES the request so the test can
/// assert the flag rode the metadata.
class _CapturingFakeClient implements InferenceClient {
  _CapturingFakeClient();

  InferenceRequest? lastRequest;

  @override
  String get id => 'capturing_fake';

  @override
  bool get isAvailable => true;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.text,
    InferenceTask.implicitlyStructuredText,
  };

  @override
  Future<bool> refreshAvailability() async => true;

  @override
  Future<void> load() async {}

  @override
  void resetAvailabilityCache() {}

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    InferenceRequest request, {
    ToolRegistry? toolRegistry,
  }) async {
    lastRequest = request;
    return InferenceResult.ok(
      InferenceResponse(
        structuredOutput: const {'text': 'decided'},
        rawOutput: 'decided',
      ),
    );
  }
}

Future<(World, _CapturingFakeClient)> _buildWorld({
  NativeLoopPolicy? policy,
}) async {
  final client = _CapturingFakeClient();
  final modelId = ModelId.create();
  final runtime = ModelRuntime(
    model: Model(id: modelId),
    client: client,
  );
  final router = ModelRouter(runtimes: {modelId: runtime});
  final world = await buildTestWorld(
    router: router,
    handler: DefaultGenerationHandler(router: router),
  );
  if (policy != null) {
    world.upsertResource(policy);
  }
  final scene = spawnScene(world);
  world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: modelId),
    ActorThreads(threads: []),
    const ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    const OpenDecision(prompt: 'one move'),
  ]);
  world.flush();
  return (world, client);
}

void main() {
  test(
    'policy set → the inference request carries end_after_tool: true',
    () async {
      final (world, client) = await _buildWorld(
        policy: NativeLoopPolicy(endAfterFirstTool: true),
      );
      syncScheduleExecutionFrame(world, explicitFrameId: 1);
      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      world.runSchedule(Schedules.project);
      world.flush();
      await world.runScheduleAsync(Schedules.actorAct);
      world.flush();

      expect(client.lastRequest, isNotNull);
      expect(client.lastRequest!.metadata['end_after_tool'], isTrue);
    },
  );

  test('no policy → the flag is absent (unchanged resume behavior)', () async {
    final (world, client) = await _buildWorld();
    syncScheduleExecutionFrame(world, explicitFrameId: 1);
    world.runSchedule(Schedules.agencyGrant);
    world.flush();
    world.runSchedule(Schedules.project);
    world.flush();
    await world.runScheduleAsync(Schedules.actorAct);
    world.flush();

    expect(client.lastRequest, isNotNull);
    expect(
      client.lastRequest!.metadata['end_after_tool'],
      isNot(true),
      reason: 'default OFF — the flag must not silently change backends '
          'that have not graduated to the on-device row',
    );
  });
}
