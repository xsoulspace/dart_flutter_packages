/// Phase 0 — Benchmark harness for the agent harness.
///
/// Measures the intelligence-efficiency properties that the tiny-context
/// (2–4k) thesis depends on, by driving the ECS world through scripted tasks
/// against a [MockGenerationHandler]. No real LLM required.
///
/// ## What it measures
///
/// - **tokens per decision**: how many tokens the projected `Situation` +
///   context fragments consume per agency moment (the real cost of a call).
/// - **llm calls per task**: how many times the model was invoked to finish
///   a task (efficiency of intelligence — agency should be sparse).
/// - **context growth**: how the projected context size evolves across turns
///   (must stay bounded, not grow toward the window limit).
/// - **task success**: whether the task reached a terminal state.
/// - **thread prune/merge**: how the mechanical graph systems behave.
///
/// ## Context budget
///
/// A benchmark declares a `tokenBudget`. Any projection that exceeds it
/// fails the benchmark — this is the enforcement that makes "≤4k" a real
/// invariant instead of an aspiration.
library;

import 'dart:async';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// A single measured run of a scripted task.
class BenchmarkRun {
  BenchmarkRun({
    required this.name,
    required this.llmCalls,
    required this.tokensPerDecision,
    required this.contextGrowth,
    required this.success,
    required this.prunedThreads,
    required this.mergedThreads,
    required this.tokenBudget,
  });

  final String name;
  final int llmCalls;
  final List<int> tokensPerDecision;
  final List<int> contextGrowth;
  final bool success;
  final int prunedThreads;
  final int mergedThreads;
  final int tokenBudget;

  /// Total tokens consumed by all decisions in this run.
  int get totalTokens => tokensPerDecision.fold(0, (a, b) => a + b);

  /// Average tokens per decision.
  double get avgTokensPerDecision =>
      tokensPerDecision.isEmpty ? 0 : totalTokens / tokensPerDecision.length;

  /// Whether any single projection exceeded the budget.
  bool get budgetExceeded => tokensPerDecision.any((t) => t > tokenBudget);

  /// Whether the run passed all assertions.
  bool get passed => success && !budgetExceeded && llmCalls > 0;
}

/// Aggregate result across multiple [BenchmarkRun]s.
class BenchmarkReport {
  BenchmarkReport(this.runs);
  final List<BenchmarkRun> runs;

  int get totalRuns => runs.length;
  int get passedRuns => runs.where((r) => r.passed).length;
  int get failedRuns => totalRuns - passedRuns;

  double get avgTokensPerDecision => runs.isEmpty
      ? 0
      : runs.fold<double>(0, (a, r) => a + r.avgTokensPerDecision) /
            runs.length;

  double get avgLlmCallsPerTask => runs.isEmpty
      ? 0
      : runs.fold<double>(0, (a, r) => a + r.llmCalls) / runs.length;

  /// A compact, human-readable summary.
  String get summary {
    final sb = StringBuffer('Harness benchmark report\n');
    sb.writeln('  runs: $passedRuns/$totalRuns passed');
    sb.writeln(
      '  avg tokens/decision: ${avgTokensPerDecision.toStringAsFixed(1)}',
    );
    sb.writeln(
      '  avg llm calls/task: ${avgLlmCallsPerTask.toStringAsFixed(1)}',
    );
    for (final r in runs) {
      sb.writeln(
        '  - ${r.name}: ${r.passed ? "PASS" : "FAIL"} '
        '(calls=${r.llmCalls}, tokens/dec=${r.avgTokensPerDecision.toStringAsFixed(1)}, '
        'growth=${r.contextGrowth}, budget=${r.tokenBudget})',
      );
    }
    return sb.toString();
  }
}

/// A scripted task: a sequence of decisions a [GenerationHandler] resolves.
///
/// Each entry is the `OpenDecision` prompt the harness will project. The
/// handler returns a canned response (optionally with tool calls).
class ScriptedTask {
  ScriptedTask({
    required this.name,
    required this.decisions,
    this.tokenBudget = 4000,
    this.projectionBudget,
    this.handler,
  });

  final String name;
  final List<String> decisions;
  final int tokenBudget;

  /// Optional projection budget (what the model actually sees). Defaults to
  /// [tokenBudget] so the benchmark exercises the cinematic cut.
  final int? projectionBudget;
  final MockGenerationHandler? handler;
}

/// Mock handler that records how many tokens each request consumed.
///
/// Token counting is a deterministic heuristic (chars / 4) — good enough to
/// enforce a budget and observe growth. A real backend would report exact
/// token counts; this keeps the benchmark LLM-free and repeatable.
class MockGenerationHandler implements GenerationHandler {
  MockGenerationHandler({this.responseText = 'ok', this.toolCalls = const []});

  final String responseText;
  final List<ToolCall> toolCalls;

  /// Tokens consumed by each request this handler served.
  final List<int> tokensServed = [];

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    // Count system prompt + prompt + all context fragments.
    var chars = request.systemPrompt.length + request.prompt.length;
    for (final f in request.contextFragments) {
      chars += '$f'.length;
    }
    tokensServed.add(_estimateTokens(chars));

    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: {'text': responseText},
      rawOutput: responseText,
      toolCalls: toolCalls,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// Rough token estimate: ~4 chars per token.
int _estimateTokens(int chars) => (chars / 4).ceil();

/// Run one [ScriptedTask] against a fresh world and return a [BenchmarkRun].
Future<BenchmarkRun> runBenchmark(ScriptedTask task) async {
  final world = World()..addPlugin(AgentPlugin());
  final handler = task.handler ?? MockGenerationHandler();
  final mockHandler = handler;
  world
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(
      ProjectionBudget(tokens: task.projectionBudget ?? task.tokenBudget),
    )
    ..upsertResource(GenerationHandlerResource()..registerDefault(handler));
  world.flush();

  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  // Graph-native memory: the actor participates in a thread, so its response
  // beats attach to the thread and accumulate into projection.
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
  final contextGrowth = <int>[];
  var llmCalls = 0;

  for (final decision in task.decisions) {
    world.upsertComponent(actor, OpenDecision(prompt: decision));
    world.flush();

    // Full cinematic cycle for this decision.
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

    // Record metrics after the decision is resolved.
    final served = mockHandler.tokensServed;
    if (served.isNotEmpty) {
      tokensPerDecision.add(served.last);
      llmCalls++;
    }

    // Measure the PROJECTED context (what the model actually sees), not raw
    // memory. This is the real tiny-context signal: count the projected beat
    // texts after the cinematic cut.
    final situation = world.getEntity(actor).$1.get<Situation>();
    final projectedChars =
        situation?.projectedBeats.fold<int>(
          0,
          (a, b) => a + _beatChars(world, b),
        ) ??
        0;
    contextGrowth.add(_estimateTokens(projectedChars));
  }

  // Count thread graph behavior.
  final pruned = world
      .query2<Thread, ThreadStatus>()
      .where((t) => t.$3.value == ThreadStatusEnum.pruned)
      .length;
  final merged = world
      .query2<Thread, ThreadStatus>()
      .where((t) => t.$3.value == ThreadStatusEnum.merged)
      .length;

  return BenchmarkRun(
    name: task.name,
    llmCalls: llmCalls,
    tokensPerDecision: tokensPerDecision,
    contextGrowth: contextGrowth,
    success: llmCalls == task.decisions.length,
    prunedThreads: pruned,
    mergedThreads: merged,
    tokenBudget: task.tokenBudget,
  );
}

int _beatChars(World world, Entity beat) {
  final (entity, valid) = world.getEntity(beat);
  if (!valid) return 0;
  final text = entity.get<TextContent>();
  return text?.text.length ?? 0;
}

/// Run a suite of tasks and return an aggregate report.
Future<BenchmarkReport> runBenchmarkSuite(List<ScriptedTask> tasks) async {
  final runs = <BenchmarkRun>[];
  for (final task in tasks) {
    runs.add(await runBenchmark(task));
  }
  return BenchmarkReport(runs);
}
