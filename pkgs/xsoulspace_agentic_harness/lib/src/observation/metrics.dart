// ignore_for_file: lines_longer_than_80_chars

/// Metrics machine for the agent harness.
///
/// A passive, LLM-agnostic recorder that taps the world's event channels and
/// snapshots per-decision telemetry, then aggregates trends over a whole run.
/// It exists to make weak spots visible: budget pressure (truncation, token
/// drift), tool-call frequency, and projection size.
///
/// The [ScenarioRunner] drives the world; this machine records what happened.
/// It does not depend on any specific model or tool.
library;

import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart';
import '../events.dart';
import '../narrative/narrative.dart';
import '../resources/resources.dart';

// ─────────────────────────────────────────────
// Per-decision telemetry
// ─────────────────────────────────────────────

/// Telemetry for a single decision (one agency moment).
class DecisionTelemetry {
  DecisionTelemetry({
    required this.actor,
    required this.prompt,
    required this.tokensUsed,
    required this.projectedBeats,
    required this.explicitAbsences,
    required this.truncated,
    required this.toolCalls,
    required this.toolResults,
    required this.llmCalls,
  });
  final String actor;
  final String prompt;
  final int tokensUsed;
  final int projectedBeats;
  final List<String> explicitAbsences;
  final bool truncated;

  /// Tools dispatched this decision, in order.
  final List<String> toolCalls;

  /// Tools that returned a result, in order.
  final List<String> toolResults;

  /// LLM generations consumed this decision.
  final int llmCalls;
}

// ─────────────────────────────────────────────
// Trends
// ─────────────────────────────────────────────

/// A metric that changed across decisions — the trend signal.
class MetricTrend {
  MetricTrend({
    required this.name,
    required this.values,
    required this.direction,
  });
  final String name;

  /// Chronological values, one per decision.
  final List<int> values;

  /// Rising / falling / flat — does the harness get better or worse over time?
  final String direction;

  double get first => values.isEmpty ? 0 : values.first.toDouble();
  double get last => values.isEmpty ? 0 : values.last.toDouble();
  double get delta => last - first;
  double get relativeDelta => first == 0 ? 0 : delta / first;
}

// ─────────────────────────────────────────────
// Aggregate report
// ─────────────────────────────────────────────

/// Aggregate telemetry for a whole run.
class MetricsReport {
  MetricsReport({required this.decisions});
  final List<DecisionTelemetry> decisions;

  int get totalDecisions => decisions.length;
  int get totalTokens => decisions.fold(0, (a, d) => a + d.tokensUsed);
  int get totalLlmCalls => decisions.fold(0, (a, d) => a + d.llmCalls);
  int get totalToolCalls => decisions.fold(0, (a, d) => a + d.toolCalls.length);
  int get totalToolResults =>
      decisions.fold(0, (a, d) => a + d.toolResults.length);
  int get truncatedDecisions => decisions.where((d) => d.truncated).length;

  double get avgTokensPerDecision =>
      decisions.isEmpty ? 0 : totalTokens / decisions.length;
  double get avgLlmCallsPerDecision =>
      decisions.isEmpty ? 0 : totalLlmCalls / decisions.length;
  double get truncationRate =>
      decisions.isEmpty ? 0 : truncatedDecisions / decisions.length;

  /// Tools dispatched but never returned — a strong weak-spot signal.
  List<String> get pendingTools {
    final returned = <String>{};
    for (final d in decisions) {
      returned.addAll(d.toolResults);
    }
    return decisions
        .expand((d) => d.toolCalls)
        .where((t) => !returned.contains(t))
        .toSet()
        .toList();
  }

  /// How tools are used across decisions.
  Map<String, int> get toolFrequency {
    final freq = <String, int>{};
    for (final d in decisions) {
      for (final t in d.toolCalls) {
        freq[t] = (freq[t] ?? 0) + 1;
      }
    }
    return freq;
  }

  MetricTrend get tokenTrend =>
      _trend('tokens', decisions.map((d) => d.tokensUsed));
  MetricTrend get beatTrend =>
      _trend('beats', decisions.map((d) => d.projectedBeats));
  MetricTrend get toolTrend =>
      _trend('tools', decisions.map((d) => d.toolCalls.length));

  MetricTrend _trend(String name, Iterable<int> values) {
    final list = values.toList();
    if (list.isEmpty) {
      return MetricTrend(name: name, values: list, direction: 'flat');
    }
    final direction = list.last > list.first
        ? 'rising'
        : list.last < list.first
        ? 'falling'
        : 'flat';
    return MetricTrend(name: name, values: list, direction: direction);
  }
}

/// Renders a [MetricsReport] as a human-readable table.
class MetricsReporter {
  const MetricsReporter();

  String render(MetricsReport report) {
    final sb = StringBuffer('Harness metrics\n');
    sb.writeln('  decisions: ${report.totalDecisions}');
    sb.writeln(
      '  avg tokens/decision: ${report.avgTokensPerDecision.toStringAsFixed(1)}',
    );
    sb.writeln(
      '  avg llm calls/decision: ${report.avgLlmCallsPerDecision.toStringAsFixed(1)}',
    );
    sb.writeln(
      '  truncation rate: ${(report.truncationRate * 100).toStringAsFixed(0)}% '
      '(${report.truncatedDecisions}/${report.totalDecisions})',
    );
    sb.writeln(
      '  tool calls: ${report.totalToolCalls} dispatched, '
      '${report.totalToolResults} returned',
    );
    sb.writeln('  dangling tools: ${report.pendingTools.join(', ')}');
    sb.writeln(
      '  token trend: ${report.tokenTrend.direction} '
      '(${report.tokenTrend.first.toStringAsFixed(1)} → '
      '${report.tokenTrend.last.toStringAsFixed(1)})',
    );
    sb.writeln('  tool frequency: ${report.toolFrequency}');
    sb.writeln('  ---');
    for (final d in report.decisions) {
      sb.writeln(
        '  [${d.actor}] "${d.prompt}" tokens=${d.tokensUsed} '
        'beats=${d.projectedBeats} calls=${d.llmCalls} '
        'tools=${d.toolCalls.join(',')} truncated=${d.truncated}',
      );
      if (d.explicitAbsences.isNotEmpty) {
        sb.writeln('      absences: ${d.explicitAbsences.join('; ')}');
      }
    }
    return sb.toString();
  }
}

// ─────────────────────────────────────────────
// Collector
// ─────────────────────────────────────────────

/// Collects per-decision telemetry. Rather than racing the ECS systems for
/// transient event channels, it tracks per-actor tool-result beats in the
/// graph (which [processToolResultsSystem] writes as [ToolResultContent]).
/// Call [beginDecision], then [endDecision] after the cinematic cycle.
class MetricsCollector {
  MetricsCollector({required this.world});

  final World world;

  final Map<int, _DecisionAccumulator> _active = {};
  final List<DecisionTelemetry> _finished = [];

  /// Channel watermark of generation responses when the current decision
  /// began. The delta at [endDecision] is the honest LLM-call count for that
  /// decision (retries and failures each consume a call).
  int _responsesSentAtBegin = 0;

  /// Begin a decision for [actor] (the actor entity). Call before a cycle.
  void beginDecision({
    required Entity actor,
    required String actorName,
    required String prompt,
  }) {
    _active[actor.hashCode] = _DecisionAccumulator(
      actor: actorName,
      prompt: prompt,
      priorBeats: _toolResultBeats(),
    );
    _responsesSentAtBegin = world.events.hasRegistered<ActorGenerateResponse>()
        ? world.events.stats<ActorGenerateResponse>().sent
        : 0;
  }

  /// Finish [actor]'s current decision and append it to the report.
  void endDecision({required Entity actor, Situation? situation}) {
    final acc = _active.remove(actor.hashCode);
    if (acc == null) return;
    // Tool results since the decision started = new ToolResultContent beats
    // created after the snapshot in [beginDecision].
    final toolResults = _newToolResultBeats(
      acc.priorBeats,
    ).map((b) => b.name).toSet().toList();
    final actorEntity = world.getEntity(actor).$1;
    final registered = actorEntity.get<ActorTools>();
    _finished.add(
      DecisionTelemetry(
        actor: acc.actor,
        prompt: acc.prompt,
        tokensUsed: situation?.tokensUsed ?? 0,
        projectedBeats: situation?.projectedBeats.length ?? 0,
        explicitAbsences: situation?.explicitAbsences ?? const [],
        truncated: situation?.truncated ?? false,
        toolCalls: registered != null ? _dispatchedTools(actor) : const [],
        toolResults: toolResults,
        // Real count: generation responses observed since this decision
        // began (includes retries). Falls back to presence-based counting
        // when no response channel traffic was seen.
        llmCalls: _llmCallsForDecision(world),
      ),
    );
  }

  /// The collected report.
  MetricsReport report() =>
      MetricsReport(decisions: List.unmodifiable(_finished));

  /// Generation responses observed since the current decision began.
  /// Retries and failures each consume an LLM call, so this is the honest
  /// tokens-per-task input — not a hardcoded 1.
  int _llmCallsForDecision(World world) {
    if (!world.events.hasRegistered<ActorGenerateResponse>()) return 0;
    final delta =
        world.events.stats<ActorGenerateResponse>().sent -
        _responsesSentAtBegin;
    return delta > 0 ? delta : 0;
  }

  /// All current tool-result beats (entity → name), in insertion (sequence) order.
  Set<Entity> _toolResultBeats() => world
      .query3<ToolResultContent, BeatStatus, TextContent>()
      .map((t) => t.$1.entity)
      .toSet();

  /// Tool-result beats present now but not at [prior] snapshot.
  List<ToolResultContent> _newToolResultBeats(Set<Entity> prior) {
    final now = _toolResultBeats();
    final added = now.difference(prior);
    final out = <ToolResultContent>[];
    for (final (entity, content, _, _)
        in world.query3<ToolResultContent, BeatStatus, TextContent>()) {
      if (added.contains(entity.entity)) out.add(content);
    }
    return out;
  }

  /// The tool names this actor is bound to (proxy for "which tools it can call").
  List<String> _dispatchedTools(Entity actor) {
    final (e, valid) = world.getEntity(actor);
    if (!valid) return const [];
    final tools = e.get<ActorTools>();
    if (tools == null) return const [];
    // Resolve the registry to enumerate the bound tools.
    final registry = world.getResource<ToolRegistryResource>().get(
      tools.registryName,
    );
    return registry?.tools.keys.map((k) => k.value).toList() ?? const [];
  }
}

class _DecisionAccumulator {
  _DecisionAccumulator({
    required this.actor,
    required this.prompt,
    required this.priorBeats,
  });
  final String actor;
  final String prompt;
  final Set<Entity> priorBeats;
}
