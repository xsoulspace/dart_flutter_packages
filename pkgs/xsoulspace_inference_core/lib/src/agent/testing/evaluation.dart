// ignore_for_file: lines_longer_than_80_chars

/// Oracle scoring and global invariant checks for LLM-free harness
/// evaluation (ADR 0003).
///
/// Oracles: per-decision expectations (expected tool calls, must-/must-not-
/// project keywords) are scored against what the harness actually did —
/// projection precision/recall become plain numbers.
///
/// Invariants: global properties asserted on any world state. A violation is
/// a harness bug regardless of scenario.
library;

import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart';
import '../events.dart';
import '../narrative/narrative.dart';
import '../observation/metrics.dart' show MetricsReport;
import '../observation/scenario_metrics.dart';

/// Oracle expectations for one decision.
class DecisionOracle {
  const DecisionOracle({
    this.expectedToolCalls = const [],
    this.mustProject = const [],
    this.mustNotProject = const [],
  });

  /// Tool names that must have been dispatched this decision (subset match).
  final List<String> expectedToolCalls;

  /// Keywords whose beats must appear in the projection.
  final List<String> mustProject;

  /// Keywords whose beats must NOT appear in the projection.
  final List<String> mustNotProject;
}

/// Oracle result for one decision.
class OracleResult {
  OracleResult({
    required this.actor,
    required this.prompt,
    required this.projectionPrecision,
    required this.projectionRecall,
    required this.missingToolCalls,
    required this.leakedKeywords,
  });

  final String actor;
  final String prompt;

  /// Fraction of projected beats relevant to the prompt keywords (0–1).
  final double projectionPrecision;

  /// Fraction of must-project keywords actually projected (0–1).
  final double projectionRecall;

  /// Expected tools never dispatched.
  final List<String> missingToolCalls;

  /// must-not-project keywords that leaked into the cut.
  final List<String> leakedKeywords;

  bool get passed => missingToolCalls.isEmpty && leakedKeywords.isEmpty;

  Map<String, dynamic> toJson() => {
    'actor': actor,
    'prompt': prompt,
    'projection_precision': projectionPrecision,
    'projection_recall': projectionRecall,
    'missing_tool_calls': missingToolCalls,
    'leaked_keywords': leakedKeywords,
    'passed': passed,
  };
}

/// Score [metrics] decisions against [oracles] (parallel lists).
///
/// Uses the world to read projected beat texts recorded in each decision's
/// telemetry window — callers pass the world after the run completes.
List<OracleResult> scoreOracles(
  World world,
  ScenarioMetrics metrics,
  List<DecisionOracle?> oracles, {
  MetricsReport? telemetry,
}) {
  final results = <OracleResult>[];
  for (var i = 0; i < metrics.decisions.length; i++) {
    final d = metrics.decisions[i];
    final oracle = i < oracles.length ? oracles[i] : null;
    if (oracle == null) continue;
    final servedTools = telemetry == null || telemetry.decisions.length <= i
        ? const <String>[]
        : telemetry.decisions[i].toolResults;

    // Projected-beat texts are not retained post-run; score against the
    // world's current beat graph filtered by the decision's actor thread.
    final texts = _beatTextsForActor(world, metrics.decisions[i].actor);
    final promptTerms = _keywords(d.prompt);

    var relevant = 0;
    for (final text in texts) {
      if (promptTerms.any(text.contains)) relevant++;
    }
    final precision = texts.isEmpty ? 1.0 : relevant / texts.length;

    var hit = 0;
    for (final kw in oracle.mustProject) {
      if (texts.any((t) => t.contains(kw))) hit++;
    }
    final recall = oracle.mustProject.isEmpty
        ? 1.0
        : hit / oracle.mustProject.length;

    final missing = [
      for (final t in oracle.expectedToolCalls)
        if (!servedTools.contains(t)) t,
    ];
    final leaked = [
      for (final kw in oracle.mustNotProject)
        if (texts.any((t) => t.contains(kw))) kw,
    ];

    results.add(
      OracleResult(
        actor: d.actor,
        prompt: d.prompt,
        projectionPrecision: precision,
        projectionRecall: recall,
        missingToolCalls: missing,
        leakedKeywords: leaked,
      ),
    );
  }
  return results;
}

List<String> _beatTextsForActor(World world, String actorName) => [
  // ScenarioRunner names are not stored on entities; score against all
  // complete text/tool beats in the graph (the post-run world IS the run's
  // residue for single-actor-per-name scenarios).
  for (final record in world.query3<TextContent, BeatStatus, BeatModality>())
    if (record.$3.value == BeatStatusEnum.complete && record.$2.text.isNotEmpty)
      record.$2.text,
];

List<String> _keywords(String text) => text
    .toLowerCase()
    .split(RegExp(r'\W+'))
    .where((t) => t.length > 2)
    .toList();

/// Global harness invariants. Returns violation descriptions; empty means
/// the world is coherent.
List<String> checkHarnessInvariants(World world) {
  final violations = <String>[];

  // 1. Agency implies OpenDecision.
  for (final record in world.query2<Actor, Agency>()) {
    if (!record.$1.has<OpenDecision>()) {
      violations.add('Agency without OpenDecision on ${record.$1.entity}');
    }
  }

  // 2. No private beat of another actor may be projected into any Situation.
  for (final record in world.query3<Actor, Agency, Situation>()) {
    final entity = record.$1;
    final situation = record.$4;
    final selfAgent = entity.get<Actor>()?.agentId;
    for (final beat in situation.projectedBeats) {
      final (be, valid) = world.getEntity(beat);
      if (!valid) continue;
      final privacy = be.get<PrivateToActor>();
      if (privacy != null && privacy.actor != entity.entity) {
        violations.add('private beat $beat leaked into a projection');
      }
      final ownerThread = be.get<BelongsToThread>()?.thread;
      if (ownerThread != null) {
        final (te, tValid) = world.getEntity(ownerThread);
        if (tValid) {
          final status = te.get<ThreadStatus>();
          if (status != null &&
              (status.value == ThreadStatusEnum.pruned ||
                  status.value == ThreadStatusEnum.merged ||
                  status.value == ThreadStatusEnum.archived)) {
            violations.add('${status.value} thread beat $beat projected');
          }
          final visibility = te.get<ThreadVisibility>();
          if (visibility != null &&
              visibility.visibleTo.isNotEmpty &&
              !visibility.visibleTo.contains(selfAgent)) {
            violations.add('restricted thread beat $beat projected');
          }
        }
      }
    }
  }

  // 3. Event channels stay consistent (no dropped overflow events).
  void channel<T extends EcsEvent>(String name) {
    if (!world.events.hasRegistered<T>()) return;
    final s = world.events.stats<T>();
    if (!s.isConsistent) violations.add('$name channel inconsistent');
  }

  channel<ActorGenerateRequest>('ActorGenerateRequest');
  channel<ActorGenerateResponse>('ActorGenerateResponse');
  channel<ActorGenerateStreamEvent>('ActorGenerateStreamEvent');
  channel<ToolCallEvent>('ToolCallEvent');
  channel<ToolResultEvent>('ToolResultEvent');

  return violations;
}
