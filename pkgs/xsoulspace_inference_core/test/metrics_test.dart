// ignore_for_file: lines_longer_than_80_chars

/// Metrics machine tests — the passive telemetry recorder and report.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/schedules.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

/// Emits a single tool call for [toolName] then a text response.
class _ToolCallHandler implements GenerationHandler {
  _ToolCallHandler(this.toolName, this.arguments);
  final String toolName;
  final Map<String, dynamic> arguments;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'ok'},
      rawOutput: 'ok',
      toolCalls: [ToolCall(name: ToolName(toolName), arguments: arguments)],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

void main() {
  group('MetricsCollector', () {
    test(
      'records a tool result that lands within the decision window',
      () async {
        final temp = await Directory.systemTemp.createTemp('metrics_');
        addTearDown(() => temp.delete(recursive: true));
        final filePath = '${temp.path}/notes.txt';
        await File(filePath).writeAsString('hello');

        final registry = ToolRegistry()
          ..register(
            readTool(
              FsToolsRoot(Directory.systemTemp.createTempSync('ecsly_t').path),
            ),
          );
        final toolResource = ToolRegistryResource();
        toolResource.register('default', registry);
        final world = await buildTestWorld(toolRegistryResource: toolResource);

        world.getResource<GenerationHandlerResource>().registerDefault(
          _ToolCallHandler('read', {'path': filePath}),
        );

        final scene = spawnScene(world);
        final actor = spawnActor(world, scene, openDecisionPrompt: 'Read it');
        world.upsertComponent(actor, const ActorTools(registryName: 'default'));
        world.flush();
        final thread = spawnThread(world, actor, scene);
        world.upsertComponent(actor, ActorThreads(threads: [thread]));
        world.flush();

        // Begin the decision window BEFORE the tool result lands.
        final collector = MetricsCollector(world: world);
        collector.beginDecision(
          actor: actor,
          actorName: 'coder',
          prompt: 'Read',
        );

        world.runSchedule(Schedules.agencyGrant);
        world.flush();
        world.runSchedule(Schedules.project);
        world.flush();
        await world.runScheduleAsync(Schedules.actorAct);
        world.flush();
        world.runSchedule(Schedules.processResponses);
        world.flush();
        world.runSchedule(Schedules.mechanical);
        world.flush();
        await Future.delayed(const Duration(milliseconds: 50));
        world.runSchedule(Schedules.mechanical);
        world.flush();

        collector.endDecision(
          actor: actor,
          situation: world.getEntity(actor).$1.get<Situation>(),
        );

        final report = collector.report();
        expect(report.totalDecisions, 1);
        expect(report.decisions.first.actor, 'coder');
        expect(report.decisions.first.toolResults, contains('read'));
        expect(report.decisions.first.toolCalls, contains('read'));
        // Result landed, so nothing dangles.
        expect(report.pendingTools, isEmpty);
        expect(report.totalTokens, greaterThan(0));
      },
    );

    test('reports totals and trends across multiple decisions', () async {
      final world = await buildTestWorld();
      final collector = MetricsCollector(world: world);
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Q');
      world.flush();

      collector.beginDecision(actor: actor, actorName: 'a', prompt: 'one');
      collector.endDecision(actor: actor, situation: null);
      collector.beginDecision(actor: actor, actorName: 'a', prompt: 'two');
      collector.endDecision(actor: actor, situation: null);

      final report = collector.report();
      expect(report.totalDecisions, 2);
      expect(report.totalLlmCalls, 0);
      expect(report.tokenTrend.values, hasLength(2));
      expect(report.tokenTrend.direction, anyOf('flat', 'rising', 'falling'));
    });

    test('reporter renders a human-readable table', () {
      const reporter = MetricsReporter();
      final report = MetricsReport(
        decisions: [
          DecisionTelemetry(
            actor: 'coder',
            prompt: 'fix parser',
            tokensUsed: 120,
            projectedBeats: 3,
            explicitAbsences: const ['1 beat off-screen'],
            truncated: false,
            toolCalls: const ['read'],
            toolResults: const ['read'],
            llmCalls: 1,
          ),
        ],
      );
      final out = reporter.render(report);
      expect(out, contains('tokens/decision'));
      expect(out, contains('read'));
    });
  });
}
