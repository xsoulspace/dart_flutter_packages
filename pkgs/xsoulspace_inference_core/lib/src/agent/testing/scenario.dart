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

import '../data_models/data_models.dart';
import '../events.dart';
import '../harness_loop.dart';
import '../narrative/narrative.dart';
import '../observation/observation.dart';
import '../resources/resources.dart';
import '../schedules.dart';
import '../systems/decision_flow_system.dart' show decisionPrecisionByPolicy;
import '../systems/projection/projection_systems.dart' show fragmentText;
import '../tools/tool_registry.dart';
import '../world_setup.dart';

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

    // Register all scenario tools under a single named registry (plus the
    // executor resource so execution works without inline closures), then
    // spawn scene/actors/threads through the shared facade.
    final toolRegistry = ToolRegistry();
    scenario.tools.forEach(toolRegistry.register);
    if (scenario.toolHook != null) {
      final tools = await scenario.toolHook!();
      tools.forEach(toolRegistry.register);
    }
    registry.register('default', toolRegistry);
    world.getResource<ToolExecutorResource>().registerAll(
      toolRegistry.tools.values,
    );
    world.flush();

    final setup = AgentWorldSetup(world: world);
    final scene = setup.spawnScene();
    final actors = setup.spawnActors(
      scenario.actors
          .map((a) => ActorSpec(name: a.name, systemPrompt: a.systemPrompt))
          .toList(),
      scene,
    );

    final decisions = <DecisionMetrics>[];
    var totalLlmCalls = 0;
    var totalTokens = 0;
    final collector = MetricsCollector(world: world);

    // Drive each actor's decisions in turn (deterministic, one at a time so
    // the metrics are attributable to a single actor/decision). Uses the
    // Schedules constants — never hardcoded ScheduleId strings — so the
    // runner cannot drift from HarnessLoop's tick order.
    for (var i = 0; i < scenario.actors.length; i++) {
      final actor = scenario.actors[i];
      final spawned = actors[i];
      final entity = spawned.entity;
      for (final prompt in actor.decisions) {
        world.upsertComponent(entity, OpenDecision(prompt: prompt));
        world.flush();
        collector.beginDecision(
          actor: entity,
          actorName: actor.name,
          prompt: prompt,
        );

        // One full cinematic cycle. The frame advances per cycle (mirrors
        // HarnessLoop._tick) so tick-based DecisionFlow policies fire
        // deterministically under the runner too.
        syncScheduleExecutionFrame(world);
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

        final situation = world.getEntity(entity).$1.get<Situation>();
        collector.endDecision(actor: entity, situation: situation);
        // Exact per-decision cut capture (ADR 0004): the projected beat texts
        // as they existed at projection time — not post-run residue.
        final projectedTexts = <String>[
          for (final beat in situation?.projectedBeats ?? const <Entity>[])
            fragmentText(world, beat),
        ];
        final metrics = DecisionMetrics(
          actor: actor.name,
          prompt: prompt,
          tokensUsed: situation?.tokensUsed ?? 0,
          projectedBeats: situation?.projectedBeats.length ?? 0,
          explicitAbsences: situation?.explicitAbsences ?? const [],
          llmCalls: 1,
          truncated: situation?.truncated ?? false,
          projectedTexts: projectedTexts,
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
      policyPrecision: decisionPrecisionByPolicy(world),
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
