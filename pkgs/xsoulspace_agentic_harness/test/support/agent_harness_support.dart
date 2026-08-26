// ignore_for_file: lines_longer_than_80_chars

/// Shared support for agent-harness tests.
///
/// Centralizes the mock LLM handler and world/scene/actor builders so each
/// focused test file stays small and asserts one thing instead of repeating
/// setup machinery. Import this surfaced names only —
/// `agent_harness_support.dart` has no `main()`, so it never runs as a test.
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/schedules.dart';
import 'package:xsoulspace_agentic_harness/src/systems/projection/projection_systems.dart'
    show fragmentText;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

/// A mock handler that simulates an LLM without requiring a real backend.
///
/// Returns a configurable [responseText] and optionally [toolCalls]. The
/// handler sends responses back to the world's event channel, mirroring how
/// a real isolate handler would consume the event channel.
class MockGenerationHandler implements GenerationHandler {
  MockGenerationHandler({
    required this.responseText,
    this.toolCalls = const [],
    this.responseOutput,
    this.delay = Duration.zero,
  });

  final String responseText;
  final List<ToolCall> toolCalls;
  final Map<String, dynamic>? responseOutput;
  final Duration delay;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }

    final output = responseOutput ?? {'text': responseText};
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: output,
      rawOutput: responseText,
      toolCalls: toolCalls,
      taskId: request.taskId,
    );

    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// A handler that throws instead of producing a response.
class ThrowingGenerationHandler implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    throw StateError('backend crashed');
  }
}

/// A handler that never responds (simulates a hung backend).
class SilentGenerationHandler implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) => Completer<ActorGenerateResponse>().future;
}

/// A handler that issues one tool call on its first invocation, then answers
/// with plain text on every later call — the minimal ReAct continuation twin.
///
/// The second call only happens if the harness re-opens a decision after the
/// tool result lands, so [calls] and [prompts] are the observable
/// "continuation happened" signals.
class WriteThenAnswerHandler implements GenerationHandler {
  WriteThenAnswerHandler({required this.firstCall});

  /// The tool call emitted on the first invocation.
  final ToolCall firstCall;

  int calls = 0;
  final List<String> prompts = [];

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    calls++;
    prompts.add(request.prompt);
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'step $calls'},
      rawOutput: 'step $calls',
      toolCalls: calls == 1 ? [firstCall] : const [],
      taskId: request.taskId,
    );
  }
}

/// Helper to build a minimal world with the agent plugin and resources.
Future<World> buildTestWorld({
  ModelRouter? router,
  ToolRegistryResource? toolRegistryResource,
  GenerationHandler? handler,
  AgencyPolicy? agencyPolicy,
  DecisionFlow? decisionFlow,
  ToolRegistry? toolRegistry,
}) async {
  final world = World()..addPlugin(AgentPlugin());
  final registryResource = toolRegistryResource ?? ToolRegistryResource();
  if (toolRegistry != null) {
    registryResource.register('default', toolRegistry);
  }

  world
    ..upsertResource(ModelRouterResource(router ?? ModelRouter()))
    ..upsertResource(registryResource);

  if (agencyPolicy != null) {
    world.upsertResource(agencyPolicy);
  }
  if (decisionFlow != null) {
    world.upsertResource(DecisionFlowResource(decisionFlow));
  }
  if (handler != null) {
    world.getResource<GenerationHandlerResource>().registerDefault(handler);
  }
  world.flush();

  return world;
}

/// Helper to spawn a scene entity.
Entity spawnScene(World world) =>
    world.spawnComponents([const Scene(), SceneFrame()]);

/// Asserts the harness is fully idle: no pending decisions, agency,
/// responses, in-flight tasks, or stranded events.
///
/// End every harness test with this. It turns "loop exited early and
/// stranded work" into a named failure at the exact channel, instead of a
/// downstream assertion failure (or worse, silence).
///
/// See docs/agent/PLAN.md → "Detecting idle-race bugs".
void expectIdle(World world) {
  final problems = <String>[];

  if (world.query2<Actor, OpenDecision>().toList().isNotEmpty) {
    problems.add('OpenDecision still pending');
  }
  if (world.query2<Actor, Agency>().toList().isNotEmpty) {
    problems.add('Agency still granted');
  }
  if (world.query2<Actor, AwaitingResponse>().toList().isNotEmpty) {
    problems.add('AwaitingResponse still set');
  }
  if (!world.getResource<TaskRegistryResource>().isEmpty) {
    problems.add(
      '${world.getResource<TaskRegistryResource>().length} task(s) in flight',
    );
  }

  void checkChannel<T extends EcsEvent>(String name) {
    if (!world.events.hasRegistered<T>()) return;
    final n = world.events.reader<T>().length;
    if (n > 0) problems.add('$n stranded $name event(s)');
  }

  // Note: ActorGenerateRequest is intentionally NOT checked — actorActSystem
  // publishes it as fire-and-forget dispatch; handlers consume the request
  // via the GenerationHandlerResource call, not by draining the channel.
  checkChannel<ActorGenerateResponse>('ActorGenerateResponse');
  checkChannel<ActorGenerateStreamEvent>('ActorGenerateStreamEvent');
  checkChannel<ToolCallEvent>('ToolCallEvent');
  checkChannel<ToolResultEvent>('ToolResultEvent');

  expect(problems, isEmpty, reason: 'harness not idle: ${problems.join('; ')}');
}

/// Helper to spawn an actor entity in a scene.
Entity spawnActor(
  World world,
  Entity sceneEntity, {
  String systemPrompt = 'You are a helpful assistant.',
  String? openDecisionPrompt,
  SchemaBundle schema = SchemaBundle.empty,
}) {
  final actorId = AgentId.create();
  final modelId = ModelId.create();
  final components = <Component>[
    Actor(agentId: actorId),
    ActorModel(modelId: modelId),
    ActorSystemPrompt(text: systemPrompt),
    PresentInScene(sceneEntity: sceneEntity),
  ];
  if (openDecisionPrompt != null) {
    components.add(OpenDecision(prompt: openDecisionPrompt, schema: schema));
  }
  return world.spawnComponents(components);
}

/// Spawn a complete text beat in [thread], indexed under [keywords].
Entity addIndexedBeat(
  World world,
  Entity thread,
  Entity speaker,
  String text,
  Iterable<String> keywords,
) {
  final beat = startBeat(world, thread, speaker, BeatModalityEnum.text);
  appendToBeat(world, beat, text);
  completeBeat(world, beat);
  indexBeat(world, beat, keywords, thread: thread);
  world.flush();
  return beat;
}

/// Drive agency grant + projection for the given world.
void projectFor(World world) {
  world.runSchedule(Schedules.agencyGrant);
  world.flush();
  world.runSchedule(Schedules.project);
  world.flush();
}

/// Drive one mechanical cinematic cycle:
/// agencyGrant → project → actorAct → processResponses → mechanical.
///
/// [settleDelay] lets async handler futures land BEFORE responses are
/// processed; [drainDelay] runs a second mechanical pass afterwards so late
/// tool completions become durable beats. End harness tests with
/// [expectIdle].
Future<void> runCycle(
  World world, {
  Duration settleDelay = const Duration(milliseconds: 50),
  Duration drainDelay = Duration.zero,
}) async {
  world.runSchedule(Schedules.agencyGrant);
  world.flush();
  world.runSchedule(Schedules.project);
  world.flush();
  await world.runScheduleAsync(Schedules.actorAct);
  world.flush();
  if (settleDelay > Duration.zero) {
    await Future<void>.delayed(settleDelay);
  }
  world.runSchedule(Schedules.processResponses);
  world.flush();
  world.runSchedule(Schedules.mechanical);
  world.flush();
  if (drainDelay > Duration.zero) {
    // Let async tool completions / handler futures land.
    await Future<void>.delayed(drainDelay);
    world.runSchedule(Schedules.mechanical);
    world.flush();
  }
}

/// Drive one decision through the canonical cinematic cycle and return exact
/// per-decision metrics (ADR 0004 capture path).
Future<ScenarioMetrics> driveOneDecision(
  World world,
  Entity actorEntity,
  String prompt,
) async {
  world.upsertComponent(actorEntity, OpenDecision(prompt: prompt));
  world.flush();
  final collector = MetricsCollector(world: world);
  collector.beginDecision(actor: actorEntity, actorName: 'a', prompt: prompt);

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

  final situation = world.getEntity(actorEntity).$1.get<Situation>();
  collector.endDecision(actor: actorEntity, situation: situation);
  final telemetry = collector.report().decisions.first;
  return ScenarioMetrics(
    name: 'driven',
    decisions: [
      DecisionMetrics(
        actor: 'a',
        prompt: prompt,
        tokensUsed: situation?.tokensUsed ?? 0,
        projectedBeats: situation?.projectedBeats.length ?? 0,
        explicitAbsences: situation?.explicitAbsences ?? const [],
        llmCalls: telemetry.llmCalls,
        truncated: situation?.truncated ?? false,
        projectedTexts: [
          for (final beat in situation?.projectedBeats ?? const <Entity>[])
            fragmentText(world, beat),
        ],
      ),
    ],
    totalLlmCalls: telemetry.llmCalls,
    totalTokens: situation?.tokensUsed ?? 0,
    prunedThreads: 0,
    mergedThreads: 0,
  );
}

/// All beats in [world] whose [TextContent] contains [text].
List<Entity> beatsWithText(World world, String text) => world
    .query2<TextContent, BeatStatus>()
    .where((t) => t.$1.get<TextContent>()?.text.contains(text) ?? false)
    .map((t) => t.$1.entity)
    .toList();
