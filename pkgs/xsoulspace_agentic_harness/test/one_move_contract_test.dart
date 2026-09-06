// ignore_for_file: lines_longer_than_80_chars

/// ADR 0028 — one move per decision (CONTRACT, backend-agnostic).
///
/// The client-parsed path: a response carrying MULTIPLE tool calls must
/// execute only the FIRST; every dropped call is recorded as a
/// contract-violation result beat (projection-visible, never executed) so
/// the next decision's cut carries the named repair hint. The native inline
/// path (`WorldToolBridge`) is gated in `resources_and_bridge_test.dart`.
///
/// Measured trigger: R9.1 investigation A (delegation_r9.md finding 13) —
/// the within-decision native tool loop accumulates append-only context the
/// harness never composed; the contract restores context ownership at every
/// token.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

Future<World> _buildWorld({
  required List<ToolCall> responseCalls,
  required int Function() alphaCalls,
  required int Function() betaCalls,
  required ModelId modelId,
}) async {
  final router = ModelRouter(inferenceClientsBuilders: {});
  router.models[modelId] = Model(id: modelId);
  final registry = ToolRegistry()
    ..register(
      ToolDef.encode(
        name: const ToolName('alpha'),
        description: 'First move — executes',
        execute: (args) async {
          alphaCalls();
          return {'moved': 'alpha'};
        },
      ),
    )
    ..register(
      ToolDef.encode(
        name: const ToolName('beta'),
        description: 'Second move in the same decision — must never execute',
        execute: (args) async {
          betaCalls();
          return {'moved': 'beta'};
        },
      ),
    );
  final world = await buildTestWorld(
    router: router,
    handler: MockGenerationHandler(
      responseText: 'moving',
      toolCalls: responseCalls,
    ),
    toolRegistry: registry,
  );
  final scene = spawnScene(world);
  world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: modelId),
    ActorThreads(threads: []),
    const ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    const OpenDecision(prompt: 'two moves in one turn'),
  ]);
  world.flush();
  return world;
}

void main() {
  test(
    'ADR 0028 contract: only the first response-carried call executes; '
    'dropped calls become contract bounce beats',
    () async {
      var alphaExecutions = 0;
      var betaExecutions = 0;
      const modelId = ModelId('m');
      final world = await _buildWorld(
        responseCalls: const [
          ToolCall(name: ToolName('alpha'), arguments: {}),
          ToolCall(name: ToolName('beta'), arguments: {}),
        ],
        alphaCalls: () => alphaExecutions++,
        betaCalls: () => betaExecutions++,
        modelId: modelId,
      );

      await HarnessLoop(world: world).runUntilIdle();

      // The loop continues across decisions (ReAct continuation re-decides
      // with the same mock response), so alpha executes once PER decision —
      // but beta is the SECOND call in every response: the contract must
      // bounce it in EVERY decision, so it never executes at all.
      expect(alphaExecutions, greaterThanOrEqualTo(1));
      expect(betaExecutions, 0, reason: 'the dropped move never executes');

      // The dropped call is recorded as a bounce beat carrying the named
      // contract — projection-visible for the NEXT decision, never run.
      final bounceBeats = world
          .query3<ToolResultContent, BeatStatus, TextContent>()
          .toList()
          .where((e) => e.$1.get<ToolResultContent>()?.name == 'beta')
          .toList();
      expect(bounceBeats, hasLength(greaterThanOrEqualTo(1)));
      final output =
          '${bounceBeats.first.$1.get<ToolResultContent>()!.output}';
      final bounce = jsonDecode(output) as Map<String, dynamic>;
      expect(bounce['contract'], 'one_move_per_decision');
      expect(bounce['executed'], 'alpha');
      expect(bounce['dropped'], 'beta');
      expect(bounce['ok'], false);
    },
  );

  test(
    'ADR 0028 contract: a single-move response is unaffected (no bounce)',
    () async {
      var alphaExecutions = 0;
      var betaExecutions = 0;
      const modelId = ModelId('m');
      final world = await _buildWorld(
        responseCalls: const [
          ToolCall(name: ToolName('alpha'), arguments: {}),
        ],
        alphaCalls: () => alphaExecutions++,
        betaCalls: () => betaExecutions++,
        modelId: modelId,
      );

      await HarnessLoop(world: world).runUntilIdle();

      expect(alphaExecutions, greaterThanOrEqualTo(1));
      final bounceBeats = world
          .query3<ToolResultContent, BeatStatus, TextContent>()
          .toList()
          .where(
            (e) =>
                ('${e.$1.get<ToolResultContent>()!.output}').contains(
                  'one_move_per_decision',
                ),
          )
          .toList();
      expect(bounceBeats, isEmpty);
    },
  );
}
