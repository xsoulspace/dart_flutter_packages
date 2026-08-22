// ignore_for_file: lines_longer_than_80_chars

/// Phase 2 — Long-horizon scaling benchmark.
///
/// Proves the core North Star claim with **no LLM**: as the beat graph grows
/// 100×, the projected context (tokens/decision) stays **flat** and projection
/// latency grows **sublinearly**. Conversation-log agents ship full history
/// every call — their token cost grows linearly with session length; this
/// harness's does not.
///
/// Design:
/// - One actor in one thread, N decisions issued sequentially. Every decision
///   produces a response beat AND a tool-result beat, so the graph grows by 2
///   beats per decision with realistic mixed content.
/// - Each decision's prompt references recent topics so keyword rays have
///   something to hit — mirroring real usage where questions relate to
///   ongoing work.
/// - We measure: tokens served per decision (what the model would see),
///   wall-clock per decision (projection + schedules), projected-beat count,
///   and facet-index size.
///
/// Assertions (the falsifiable claims):
/// 1. tokens/decision at the END of the run ≤ tokens/decision at the START
///    × flatness factor (default 1.25). Flat means bounded forever.
/// 2. Per-decision latency at the end ≤ start latency × growth factor
///    (default 4×) — allows superlinear constants but forbids blowups.
/// 3. No projection ever exceeded the token budget.

import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Result of one long-horizon run.
class LongHorizonResult {
  LongHorizonResult({
    required this.decisions,
    required this.tokensPerDecision,
    required this.latencyMicrosPerDecision,
    required this.projectedBeatsPerDecision,
    required this.totalBeats,
    required this.indexKeywords,
    required this.tokenBudget,
  });

  final int decisions;
  final List<int> tokensPerDecision;
  final List<int> latencyMicrosPerDecision;
  final List<int> projectedBeatsPerDecision;
  final int totalBeats;
  final int indexKeywords;
  final int tokenBudget;

  /// Mean tokens over the first 10% of decisions (warm-up window).
  double get earlyAvgTokens {
    final w = tokensPerDecision.take((decisions * 0.1).ceil()).toList();
    if (w.isEmpty) return 0;
    return w.fold<int>(0, (a, b) => a + b) / w.length;
  }

  /// Mean tokens over the last 10% of decisions (steady-state window).
  double get lateAvgTokens {
    final w = tokensPerDecision
        .skip(tokensPerDecision.length - (decisions * 0.1).ceil())
        .toList();
    if (w.isEmpty) return 0;
    return w.fold<int>(0, (a, b) => a + b) / w.length;
  }

  /// Flatness ratio: late/early. ~1.0 means perfectly bounded context.
  double get flatnessRatio =>
      earlyAvgTokens == 0 ? 0 : lateAvgTokens / earlyAvgTokens;

  /// Mean latency over the first 10% vs last 10% of decisions.
  double get earlyAvgLatency {
    final w = latencyMicrosPerDecision.take((decisions * 0.1).ceil()).toList();
    if (w.isEmpty) return 0;
    return w.fold<int>(0, (a, b) => a + b) / w.length;
  }

  double get lateAvgLatency {
    final w = latencyMicrosPerDecision
        .skip(latencyMicrosPerDecision.length - (decisions * 0.1).ceil())
        .toList();
    if (w.isEmpty) return 0;
    return w.fold<int>(0, (a, b) => a + b) / w.length;
  }

  /// Latency growth ratio: late/early. Sublinear-ish means well under beats
  /// growth (beats grow `decisions`×; anything ≪ that is fine).
  double get latencyGrowthRatio =>
      earlyAvgLatency == 0 ? 0 : lateAvgLatency / earlyAvgLatency;

  bool get budgetExceeded => tokensPerDecision.any((t) => t > tokenBudget);

  /// Render a human-readable report.
  String get report {
    final sb = StringBuffer('Long-horizon scaling benchmark\n');
    sb.writeln(
      '  decisions: $decisions, total beats: $totalBeats, '
      'index keywords: $indexKeywords',
    );
    sb.writeln(
      '  tokens/decision: early=${earlyAvgTokens.toStringAsFixed(1)} '
      'late=${lateAvgTokens.toStringAsFixed(1)} '
      'flatness=${flatnessRatio.toStringAsFixed(2)}x',
    );
    sb.writeln(
      '  latency ms/decision: '
      'early=${(earlyAvgLatency / 1000).toStringAsFixed(2)} '
      'late=${(lateAvgLatency / 1000).toStringAsFixed(2)} '
      'growth=${latencyGrowthRatio.toStringAsFixed(2)}x',
    );
    sb.writeln('  budget exceeded: $budgetExceeded');
    return sb.toString();
  }
}

/// Run [decisions] sequential decisions against one actor whose graph grows
/// every turn. Returns measured metrics.
Future<LongHorizonResult> runLongHorizonBenchmark({
  int decisions = 1000,
  int tokenBudget = 4000,
}) async {
  final world = World()..addPlugin(AgentPlugin());
  final handler = _RecordingHandler();
  world
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(ProjectionBudget(tokens: tokenBudget))
    ..upsertResource(GenerationHandlerResource()..registerDefault(handler));
  world.flush();

  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: ModelId.create()),
    PresentInScene(sceneEntity: scene),
    ActorThreads(threads: []),
  ]);
  world.flush();
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  world.flush();

  final tokensPerDecision = <int>[];
  final latencies = <int>[];
  final projectedBeats = <int>[];

  for (var i = 0; i < decisions; i++) {
    // The prompt references two earlier "topics" so keyword rays hit real
    // content — mirrors how a coding agent's next question relates to prior
    // work rather than being random noise.
    final topicA = 'topic${i ~/ 50}';
    final topicB = 'topic${(i ~/ 50).clamp(0, 9999)}';
    world.upsertComponent(
      actor,
      OpenDecision(prompt: 'Continue working on $topicA and $topicB step $i'),
    );
    world.flush();

    final sw = Stopwatch()..start();
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
    sw.stop();
    latencies.add(sw.elapsedMicroseconds);

    final situation = world.getEntity(actor).$1.get<Situation>();
    tokensPerDecision.add(handler.tokensServed.last);
    projectedBeats.add(situation?.projectedBeats.length ?? 0);
  }

  final totalBeats = world.query2<BeatStatus, TextContent>().length;
  final indexKeywords = world.getResource<FacetIndex>().byKeyword.length;

  return LongHorizonResult(
    decisions: decisions,
    tokensPerDecision: tokensPerDecision,
    latencyMicrosPerDecision: latencies,
    projectedBeatsPerDecision: projectedBeats,
    totalBeats: totalBeats,
    indexKeywords: indexKeywords,
    tokenBudget: tokenBudget,
  );
}

/// Handler that records tokens served and writes a growing response each turn
/// (like a real agent producing progressively more context-relevant output).
class _RecordingHandler implements GenerationHandler {
  final tokensServed = <int>[];
  var turn = 0;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    var chars = request.systemPrompt.length + request.prompt.length;
    for (final f in request.contextFragments) {
      chars += '$f'.length;
    }
    tokensServed.add((chars / 4).ceil());

    // Response mentions its turn's topic so later rays can hit it.
    final text =
        'topic${turn ~/ 50} completed step $turn with detailed '
        'findings filler filler filler filler filler filler filler filler';
    turn++;

    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: {'text': text},
      rawOutput: text,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// CLI entry: `dart run benchmark/long_horizon_benchmark.dart [decisions]`
Future<void> main(List<String> args) async {
  final decisions = args.isNotEmpty ? int.tryParse(args.first) ?? 1000 : 1000;
  stdout.writeln('Running long-horizon benchmark: $decisions decisions...');
  final result = await runLongHorizonBenchmark(decisions: decisions);
  stdout.writeln(result.report);

  // Falsifiable assertions — non-zero exit on failure so CI can gate.
  // Flatness is measured over 10% windows; short runs are noisy (warm-up
  // effects dominate), so the gate tightens with run length.
  final maxFlatness = decisions < 500 ? 1.40 : 1.25;
  const maxLatencyGrowth = 4.0;
  var failed = false;
  if (result.flatnessRatio > maxFlatness) {
    stdout.writeln(
      'FAIL: flatness ${result.flatnessRatio.toStringAsFixed(2)}x > '
      '$maxFlatness — context is growing with session length.',
    );
    failed = true;
  }
  if (result.latencyGrowthRatio > maxLatencyGrowth) {
    stdout.writeln(
      'FAIL: latency growth ${result.latencyGrowthRatio.toStringAsFixed(2)}x '
      '> $maxLatencyGrowth — projection is not scaling.',
    );
    failed = true;
  }
  if (result.budgetExceeded) {
    stdout.writeln('FAIL: a projection exceeded the token budget.');
    failed = true;
  }
  exit(failed ? 1 : 0);
}
