// ignore_for_file: lines_longer_than_80_chars

/// Scenario stress-testing for the agent harness.
///
/// A [Scenario] is a declarative description of a multi-actor, multi-topic,
/// tool-using run. [ScenarioRunner] drives the real [HarnessLoop] against a
/// real [GenerationHandler] (e.g. Apple Foundation) and records per-decision
/// metrics so we can find and fix the harness's weak spots under load.
///
/// This is deliberately LLM-agnostic: the runner only needs a
/// [GenerationHandler]. The Apple Foundation wiring lives in the host app.
library;

import 'dart:async';

import 'package:ecsly/ecsly.dart';

import 'agent.dart';
import 'components.dart';
import 'events.dart';
import 'harness_loop.dart';
import 'metrics.dart';
import 'narrative.dart';
import 'resources.dart';

// ─────────────────────────────────────────────
// Scenario model
// ─────────────────────────────────────────────

/// A single actor in a [Scenario]: an identity, a system prompt, and the
/// topics (OpenDecision prompts) it must resolve.
class ScenarioActor {
  ScenarioActor({
    required this.name,
    required this.systemPrompt,
    required this.decisions,
  });
  final String name;
  final String systemPrompt;
  final List<String> decisions;
}

/// A hook that may register additional tools mid-run.
///
/// Called once before the run starts. Return tools to add to the registry;
/// the runner registers them so the model can use them. This exercises the
/// "dynamically add tools if needed" path.
typedef ScenarioToolHook = Future<List<ToolDef>> Function();

/// A declarative stress scenario.
class Scenario {
  Scenario({
    required this.name,
    required this.actors,
    this.tools = const [],
    this.toolHook,
    this.tokenBudget = 4000,
    this.maxConcurrent = 8,
  });
  final String name;
  final List<ScenarioActor> actors;
  final List<ToolDef> tools;

  /// Optional hook to add tools dynamically before the run.
  final ScenarioToolHook? toolHook;
  final int tokenBudget;
  final int maxConcurrent;
}

// ─────────────────────────────────────────────
// Metrics
// ─────────────────────────────────────────────

/// Metrics for one decision (one agency moment).
class DecisionMetrics {
  DecisionMetrics({
    required this.actor,
    required this.prompt,
    required this.tokensUsed,
    required this.projectedBeats,
    required this.explicitAbsences,
    required this.llmCalls,
    required this.truncated,
  });
  final String actor;
  final String prompt;
  final int tokensUsed;
  final int projectedBeats;
  final List<String> explicitAbsences;
  final int llmCalls;
  final bool truncated;
}

/// Aggregate metrics for a whole [Scenario] run.
class ScenarioMetrics {
  ScenarioMetrics({
    required this.name,
    required this.decisions,
    required this.totalLlmCalls,
    required this.totalTokens,
    required this.prunedThreads,
    required this.mergedThreads,
    MetricsReport? telemetry,
  }) : telemetry = telemetry ?? MetricsReport(decisions: const []);
  final String name;
  final List<DecisionMetrics> decisions;
  final int totalLlmCalls;
  final int totalTokens;
  final int prunedThreads;
  final int mergedThreads;

  /// Richer telemetry (tool calls/results, trends) from [MetricsCollector].
  final MetricsReport telemetry;

  double get avgTokensPerDecision =>
      decisions.isEmpty ? 0 : totalTokens / decisions.length;
  double get avgLlmCallsPerDecision =>
      decisions.isEmpty ? 0 : totalLlmCalls / decisions.length;
}

// ─────────────────────────────────────────────
// Runner
// ─────────────────────────────────────────────

/// Drives a [Scenario] through the real [HarnessLoop] and records metrics.
class ScenarioRunner {
  ScenarioRunner({
    required this.world,
    required this.handler,
    this.toolRegistryResource,
  });

  final World world;
  final GenerationHandler handler;
  final ToolRegistryResource? toolRegistryResource;

  /// Run [scenario] and return the collected metrics.
  Future<ScenarioMetrics> run(Scenario scenario) async {
    final registry =
        toolRegistryResource ?? world.getResource<ToolRegistryResource>();
    world
      ..upsertResource(ProjectionBudget(tokens: scenario.tokenBudget))
      ..upsertResource(AgencyPolicy(maxConcurrent: scenario.maxConcurrent));
    world.getResource<GenerationHandlerResource>().registerDefault(handler);
    // Register all scenario tools under a single named registry and bind every
    // actor to it, so the model can actually call them. This is the actor→tool
    // binding that makes the first run meaningful.
    final toolRegistry = ToolRegistry();
    for (final tool in scenario.tools) {
      toolRegistry.register(tool);
    }
    if (scenario.toolHook != null) {
      for (final tool in await scenario.toolHook!()) {
        toolRegistry.register(tool);
      }
    }
    registry.register('default', toolRegistry);
    world.flush();

    final scene = world.spawnComponents([const Scene(), SceneFrame()]);
    final actorEntities = <Entity>[];
    for (final actor in scenario.actors) {
      final e = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        ActorSystemPrompt(text: actor.systemPrompt),
        ActorThreads(threads: []),
        const ActorTools(registryName: 'default'),
        PresentInScene(sceneEntity: scene),
      ]);
      actorEntities.add(e);
    }
    world.flush();

    // Give each actor a thread so projection can ray-trace its own beats.
    for (final e in actorEntities) {
      final thread = spawnThread(world, e, scene);
      world.upsertComponent(e, ActorThreads(threads: [thread]));
    }
    world.flush();

    final decisions = <DecisionMetrics>[];
    var totalLlmCalls = 0;
    var totalTokens = 0;
    final collector = MetricsCollector(world: world);

    // Drive each actor's decisions in turn (deterministic, one at a time so
    // the metrics are attributable to a single actor/decision).
    for (var i = 0; i < scenario.actors.length; i++) {
      final actor = scenario.actors[i];
      final entity = actorEntities[i];
      for (final prompt in actor.decisions) {
        world.upsertComponent(entity, OpenDecision(prompt: prompt));
        world.flush();
        collector.beginDecision(
          actor: entity,
          actorName: actor.name,
          prompt: prompt,
        );

        // One full cinematic cycle.
        world.runSchedule('AgencyGrant');
        world.flush();
        world.runSchedule('Project');
        world.flush();
        await world.runScheduleAsync('ActorAct');
        world.flush();
        world.runSchedule('ProcessResponses');
        world.flush();
        world.runSchedule('Mechanical');
        world.flush();

        final situation = world.getEntity(entity).$1.get<Situation>();
        collector.endDecision(actor: entity, situation: situation);
        final metrics = DecisionMetrics(
          actor: actor.name,
          prompt: prompt,
          tokensUsed: situation?.tokensUsed ?? 0,
          projectedBeats: situation?.projectedBeats.length ?? 0,
          explicitAbsences: situation?.explicitAbsences ?? const [],
          llmCalls: 1,
          truncated: situation?.truncated ?? false,
        );
        decisions.add(metrics);
        totalLlmCalls += metrics.llmCalls;
        totalTokens += metrics.tokensUsed;
      }
    }

    final pruned = world
        .query2<Thread, ThreadStatus>()
        .where((t) => t.$3.value == ThreadStatusEnum.pruned)
        .length;
    final merged = world
        .query2<Thread, ThreadStatus>()
        .where((t) => t.$3.value == ThreadStatusEnum.merged)
        .length;

    return ScenarioMetrics(
      name: scenario.name,
      decisions: decisions,
      totalLlmCalls: totalLlmCalls,
      totalTokens: totalTokens,
      prunedThreads: pruned,
      mergedThreads: merged,
      telemetry: collector.report(),
    );
  }
}

// ─────────────────────────────────────────────
// Reporter
// ─────────────────────────────────────────────

/// Prints a human-readable stress-test report from [ScenarioMetrics].
class ScenarioMetricsReporter {
  const ScenarioMetricsReporter();

  /// Render [metrics] as a multi-line report string.
  String render(ScenarioMetrics metrics) {
    final sb = StringBuffer('Scenario: ${metrics.name}\n');
    sb.writeln('  decisions: ${metrics.decisions.length}');
    sb.writeln(
      '  avg tokens/decision: ${metrics.avgTokensPerDecision.toStringAsFixed(1)}',
    );
    sb.writeln(
      '  avg llm calls/decision: ${metrics.avgLlmCallsPerDecision.toStringAsFixed(1)}',
    );
    sb.writeln('  total tokens: ${metrics.totalTokens}');
    sb.writeln('  pruned threads: ${metrics.prunedThreads}');
    sb.writeln('  merged threads: ${metrics.mergedThreads}');
    sb.writeln('  ---');
    for (final d in metrics.decisions) {
      sb.writeln(
        '  [${d.actor}] "${d.prompt}" '
        'tokens=${d.tokensUsed} beats=${d.projectedBeats} '
        'calls=${d.llmCalls} truncated=${d.truncated}',
      );
      if (d.explicitAbsences.isNotEmpty) {
        sb.writeln('      absences: ${d.explicitAbsences.join('; ')}');
      }
    }
    return sb.toString();
  }
}
