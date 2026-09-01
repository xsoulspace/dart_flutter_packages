// ignore_for_file: lines_longer_than_80_chars

/// 20-task coding suite runner.
///
/// For each task:
/// 1. Create a fresh jail directory, seed fixture files.
/// 2. Build a harness world (AgentPlugin + ModelRouter + fsTools jailed to the
///    task dir) and spawn one actor with the task prompt as OpenDecision.
/// 3. Run HarnessLoop.runUntilIdle().
/// 4. Evaluate deterministic checkers against the jail.
/// 5. Record pass/fail + metrics (tokens, LLM calls, wall clock) to a JSONL
///    trace for diffing across runs/agents.
///
/// The runner is agent-agnostic: any [GenerationHandler] works, so the same
/// suite can be pointed at AFM (via AppleFoundationNativeClient) or at pi
/// (via a local OpenAI-compatible shim) for apples-to-apples comparison.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../xsoulspace_agentic_harness.dart';
import '../../tooling/act_with_project.dart' show actWithProjectTool;
import '../../tools/fs_tools.dart';
import 'checkers.dart';
import 'task_spec.dart';

/// Result of running one task.
class TaskResult {
  TaskResult({
    required this.taskId,
    required this.category,
    required this.passed,
    required this.checkerResults,
    required this.wallClock,
    required this.tokensUsed,
    required this.cumulativeTokens,
    required this.llmCalls,
    required this.toolCalls,
    this.backend = 'harness',
    this.model = 'unknown',
    this.failureMode = '',
    this.escalations = 0,
    this.transientErrors = 0,
  });

  final String taskId;
  final String category;
  final bool passed;
  final List<CheckerResult> checkerResults;
  final Duration wallClock;

  /// Last-decision projection size (legacy field, kept for comparability
  /// with earlier traces).
  final int tokensUsed;

  /// Honest spend: sum of every decision's projection size. [tokensUsed]
  /// alone measures the LAST cut, not task spend — see
  /// docs/agent/results_plan_falsification.md §accounting caveat.
  final int cumulativeTokens;
  final int llmCalls;
  final List<String> toolCalls;

  /// Which backend produced this result (e.g. 'afm', 'openrouter',
  /// 'scripted') — trace rows from different runners must stay comparable.
  final String backend;

  /// Concrete model identifier as reported by the backend (wire model id).
  final String model;

  /// Phase 4 honesty metric: why the task failed, classified
  /// deterministically. Empty on pass.
  /// One of: timeout, tool-error, transient-errors, wrong-edit, no-llm.
  final String failureMode;

  /// Number of escalation requests observed for this task's actor.
  /// Structurally 0 for single-tier backends (AFM alone) — recorded so the
  /// escalation-rate column is honest rather than absent (PLAN Phase 4).
  final int escalations;

  /// Generation responses that arrived with a non-empty [error] — e.g. AFM
  /// GenerationError -1 framework flakiness. NOT silently retried away:
  /// this count feeds the recovery benchmark follow-up.
  final int transientErrors;

  Map<String, Object?> toJson() => {
    'task_id': taskId,
    'category': category,
    'backend': backend,
    'model': model,
    'passed': passed,
    'wall_clock_ms': wallClock.inMilliseconds,
    'tokens_used': tokensUsed,
    'cumulative_tokens': cumulativeTokens,
    'llm_calls': llmCalls,
    'tool_calls': toolCalls,
    if (failureMode.isNotEmpty) 'failure_mode': failureMode,
    'escalations': escalations,
    'transient_errors': transientErrors,
    'checkers': [
      for (final c in checkerResults) {'passed': c.passed, 'detail': c.detail},
    ],
  };
}

/// Aggregate suite result.
class SuiteResult {
  SuiteResult({required this.results});
  final List<TaskResult> results;

  int get total => results.length;
  int get passedCount => results.where((r) => r.passed).length;
  double get passRate => total == 0 ? 0 : passedCount / total;
  Duration get totalWallClock =>
      results.fold(Duration.zero, (a, r) => a + r.wallClock);
  int get totalTokens => results.fold(0, (a, r) => a + r.tokensUsed);

  /// Markdown summary table — the headline artifact for North Star updates.
  String toMarkdown({String label = 'harness'}) {
    final b = StringBuffer()
      ..writeln('| task | category | pass | wall | tokens |')
      ..writeln('|---|---|---|---|---|');
    for (final r in results) {
      b.writeln(
        '| ${r.taskId} | ${r.category} | ${r.passed ? '✅' : '❌'} '
        '| ${r.wallClock.inMilliseconds}ms | ${r.tokensUsed} |',
      );
    }
    b
      ..writeln()
      ..writeln(
        '**$label**: $passedCount/$total passed '
        '(${(passRate * 100).toStringAsFixed(0)}%), '
        '$totalTokens tokens total, '
        '${totalWallClock.inSeconds}s wall clock.',
      );
    return b.toString();
  }
}

/// Harness-side scaffolding, applied identically to every arm/backend: the
/// runner already knows the seeded workspace deterministically, so it states
/// those facts in the system prompt instead of spending model rounds
/// rediscovering them (externalized cognition — the world carries what the
/// model should not have to guess). Part of the measured context surface.
String _systemPromptWithLayout(CodingTask task) {
  if (task.fixtures.isEmpty) return task.systemPrompt;
  final layout = task.fixtures.map((f) => '- ${f.path}').join('\n');
  return '${task.systemPrompt}\n\n'
      'Workspace layout (paths are relative to the workspace root):\n'
      '$layout\n'
      'All tool paths are relative to the workspace root.';
}

/// Runs [CodingTask]s through the real harness loop.
class CodingSuiteRunner {
  CodingSuiteRunner({
    required this.buildHandler,
    this.jailParent,
    this.modelId = const ModelId('suite-model'),
    this.modelName = DefaultModelNames.appleFoundation,
    this.router,
    this.maxConcurrent = 1,
    this.maxCheckerRetries = 0,
    this.maxToolRounds = 16,
    this.taskTimeoutMinutes = 8,
    this.resumeFromTrace,
    this.backendLabel = 'harness',
    this.modelLabel = 'unknown',
    this.extraTools = const [],
  });

  /// Builds the generation handler for each run (fresh per task so state
  /// never leaks between tasks). Receives the task so handlers can key
  /// behavior on [CodingTask.id].
  final GenerationHandler Function(CodingTask task) buildHandler;

  /// Additional tools registered next to fs tools (e.g. `patch_file`,
  /// `verify_pack`). Factories receive the per-task jail root. Additive
  /// seam — no runner fork.
  final List<ToolDef Function(String jailRoot)> extraTools;

  /// Parent directory for per-task jails. Defaults to a system temp dir.
  final Directory? jailParent;

  /// Model id registered in the router for the run's single model.
  final ModelId modelId;

  /// Registered [Model.name] — must match a key in the handler's router
  /// `inferenceClientsBuilders` (e.g. [DefaultModelNames.appleFoundation] for
  /// the AFM bin, [OpenRouterModelNames.openRouter] for OpenRouter).
  final ModelName modelName;

  /// Shared router: registered as [ModelRouterResource] AND used by the
  /// host-built handler, so model resolution cannot desynchronize. When null
  /// a fresh empty router is created (scripted runs without real backends).
  final ModelRouter? router;

  /// Concurrency gate passed to [AgencyPolicy]. AFM is serial on-device;
  /// keep at 1 for fair single-actor measurements.
  final int maxConcurrent;

  /// How many times failing checkers are mechanically fed back to the actor
  /// as a new [OpenDecision]. Zero disables the verifier loop. Each retry is
  /// an honest LLM call — the retry loop itself is deterministic.
  final int maxCheckerRetries;

  /// ReAct tool rounds allowed per decision chain (AgencyPolicy bound).
  /// Small local models benefit from headroom; hosted models rarely need it.
  final int maxToolRounds;

  /// Hard wall-clock budget per task (all checker retries included). A model
  /// looping tool calls must not eat the suite; on timeout the workspace is
  /// still evaluated — partial progress often satisfies checkers.
  final int taskTimeoutMinutes;

  /// Path to a previous JSONL trace. Tasks already present there are skipped
  /// so an interrupted run resumes instead of paying ~45min again.
  final String? resumeFromTrace;

  /// Stamp written into every trace row (see [TaskResult.backend]).
  final String backendLabel;

  /// Stamp written into every trace row (see [TaskResult.model]).
  final String modelLabel;

  Future<TaskResult> runTask(CodingTask task) async {
    final parent = jailParent ?? Directory.systemTemp;
    final jail = await parent.createTemp('coding_suite_${task.id}_');
    try {
      // Seed fixtures.
      for (final f in task.fixtures) {
        final file = File('${jail.path}/${f.path}');
        await file.parent.create(recursive: true);
        await file.writeAsString(f.content);
      }

      // Build the world exactly like the production example path.
      final world = World()..addPlugin(AgentPlugin());
      // Use the host-provided router when given so the handler and the
      // resource registry see the SAME builders + model registry. Two
      // routers would desynchronize: the handler's fallback Model defaults
      // to appleFoundation and silently misses backend-specific clients.
      final router = this.router ?? ModelRouter(inferenceClientsBuilders: {});
      router.models[modelId] = Model(id: modelId, name: modelName);
      // Meaning-executor arms are STRUCTURALLY move-dense: the whole point
      // is many tiny meaning moves instead of one big write. The default
      // 16-round chain cap would cut them mid-build — lift it for the
      // intent-closure category (a recorded I1/I2 matrix dimension: tiny
      // moves trade round overhead for per-move tokens).
      final rounds = task.category == TaskCategory.intentClosure
          ? (maxToolRounds < 48 ? 48 : maxToolRounds)
          : maxToolRounds;
      world
        ..upsertResource(ModelRouterResource(router))
        ..upsertResource(ToolRegistryResource())
        ..upsertResource(
          AgencyPolicy(
            maxConcurrent: maxConcurrent,
            maxToolRounds: rounds,
          ),
        )
        ..flush();

      final handler = buildHandler(task);
      // Count errored generations (framework flakiness, backend failures)
      // WITHOUT masking them: the retry policy is unchanged; we only observe.
      var transientErrors = 0;
      // Honest cumulative token accounting (see TaskResult.cumulativeTokens).
      final tokenTotal = <int>[0];
      final GenerationHandler metered = CumulativeTokenMeter(handler, tokenTotal);
      world.getResource<GenerationHandlerResource>().registerDefault(
        _ErrorCountingHandler(metered, () => transientErrors++),
      );

      final registry = ToolRegistry();
      fsTools(FsToolsRoot(jail.path)).forEach(registry.register);
      // Stage I: meaning-executor arm — intent-closure tasks speak through
      // meaning moves (act_with_project + intents); the host materializer
      // compiles the op chains into the suite's program.dart contract.
      if (task.category == TaskCategory.intentClosure) {
        registry.register(actWithProjectTool(
          world: world,
          materialize: () async {
            final src = materializeMeaningProgram(world);
            // NB: use explicit ${} — bare $jail.path would interpolate only
            // `jail` and treat `.path/program.dart` as a literal suffix.
            File('${jail.path}/program.dart').writeAsStringSync(src);
            return {
              'path': 'program.dart',
              'materialized': true,
              'intents': [for (final i in listIntents(world)) i['name']],
              // Host-side chain validation: broken impl chains are caught
              // NOW (op ids included) instead of one checker round later.
              'problems': validateMeaningProgram(world),
            };
          },
        ));
        registry.register(intentDefineTool(world));
        registry.register(intentCallTool(world));
      }
      for (final factory in extraTools) {
        registry.register(factory(jail.path));
      }
      world.getResource<ToolRegistryResource>().register('default', registry);

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      // Give the actor a thread BEFORE spawning so tool/assistant beats
      // attach to it (attachBeatToActorThread) and projection can ray-trace
      // the conversation into continuation decisions. Without this the model
      // continues blind after each tool result (mirrors world_setup.spawnActors).
      final actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: modelId),
        ActorSystemPrompt(text: _systemPromptWithLayout(task)),
        ActorThreads(threads: []),
        const ActorTools(registryName: 'default'),
        PresentInScene(sceneEntity: scene),
        OpenDecision(prompt: task.prompt),
      ]);
      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();

      final sw = Stopwatch()..start();
      final loop = HarnessLoop(world: world);
      // Hard per-task bound: a model that loops tool calls must not eat the
      // whole suite wall clock. On timeout the workspace is still checked —
      // partial progress often satisfies checkers.
      final taskBudget = Duration(minutes: taskTimeoutMinutes);
      // Watermarks for honest accounting: every generation response is one
      // LLM call.
      int responsesSent() => world.events.hasRegistered<ActorGenerateResponse>()
          ? world.events.stats<ActorGenerateResponse>().sent
          : 0;
      final responsesSentAtStart = responsesSent();

      // Verifier-in-the-loop: run the agent, evaluate checkers, and on
      // failure mechanically (no LLM) convert each failing checker into a
      // new OpenDecision. Bounded by [maxCheckerRetries].
      var checkerResults = <CheckerResult>[];
      var checkerRetry = 0;
      while (true) {
        await loop.runUntilIdle();
        checkerResults = [
          for (final c in task.checkers) evaluateChecker(c, jail.path),
        ];
        final allPassed =
            checkerResults.isNotEmpty && checkerResults.every((c) => c.passed);
        if (allPassed || checkerRetry >= maxCheckerRetries) break;
        checkerRetry++;
        final failures = [
          for (final (i, c) in checkerResults.indexed)
            if (!c.passed)
              'checker #$i (${task.checkers[i].type} '
                  '${task.checkers[i].path}): ${c.detail}',
        ].join('\n');
        world.upsertComponent(
          actor,
          OpenDecision(
            prompt:
                'Your previous attempt did not satisfy the task verification. '
                'Failing checks:\n$failures\n\n'
                'Fix the workspace so all checks pass. Original task:\n'
                '${task.prompt}',
          ),
        );
        world.flush();
      }
      sw.stop();

      final llmCalls = responsesSent() - responsesSentAtStart;

      // Collect metrics from the actor's Situation + tool-result beats.
      var tokensUsed = 0;
      for (final (_, _, situation) in world.query2<Actor, Situation>()) {
        tokensUsed += situation.tokensUsed;
      }
      final toolCalls = <String>[];
      for (final record
          in world.query3<ToolResultContent, BeatStatus, TextContent>()) {
        toolCalls.add(record.$2.name);
      }

      // Escalation accounting (Phase 4 binding metric). Single-tier
      // backends structurally produce 0 — recorded explicitly.
      final escalations = world.query2<Actor, EscalationRequest>().length;

      // Deterministic failure-mode classification. Failures are data.
      final passed =
          checkerResults.isNotEmpty && checkerResults.every((c) => c.passed);
      String failureMode = '';
      if (!passed) {
        final anyToolError = world.query<ToolResultContent>().any(
          (r) => r.$2.output.toString().contains('"error"'),
        );
        if (sw.elapsed >= taskBudget) {
          failureMode = 'timeout';
        } else if (llmCalls == 0) {
          failureMode = 'no-llm';
        } else if (transientErrors > 0 && checkerRetry == maxCheckerRetries) {
          failureMode = 'transient-errors';
        } else if (anyToolError) {
          failureMode = 'tool-error';
        } else {
          // Checkers ran and genuinely disagreed with the workspace state.
          failureMode = 'wrong-edit';
        }
      }

      return TaskResult(
        taskId: task.id,
        category: task.category.yamlName,
        passed:
            checkerResults.isNotEmpty && checkerResults.every((c) => c.passed),
        checkerResults: checkerResults,
        wallClock: sw.elapsed,
        tokensUsed: tokensUsed,
        cumulativeTokens: tokenTotal[0],
        llmCalls: llmCalls,
        toolCalls: toolCalls,
        backend: backendLabel,
        failureMode: failureMode,
        escalations: escalations,
        transientErrors: transientErrors,
        model: modelLabel,
      );
    } finally {
      jail.delete(recursive: true);
    }
  }

  /// Run all tasks; append one JSON line per task to [tracePath] if given.
  /// [filter] keeps only tasks whose id contains it (case-insensitive).
  Future<SuiteResult> runAll(
    List<CodingTask> tasks, {
    String? tracePath,
    String? filter,
  }) async {
    final selected = filter == null || filter.isEmpty
        ? tasks
        : tasks
              .where((t) => t.id.toLowerCase().contains(filter.toLowerCase()))
              .toList();
    final done = <String>{};
    final resumePath = resumeFromTrace;
    if (resumePath != null && File(resumePath).existsSync()) {
      for (final line in File(resumePath).readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        try {
          done.add(
            (jsonDecode(line) as Map<String, dynamic>)['task_id'] as String,
          );
        } on FormatException {
          // Torn last line from a killed run — ignore.
        }
      }
    }
    final results = <TaskResult>[];
    var skipped = 0;
    for (final task in selected) {
      if (done.contains(task.id)) {
        skipped++;
        stdout.writeln('▶ ${task.id} — already in trace, skipping');
        continue;
      }
      stdout.writeln('▶ ${task.id} (${task.category.yamlName})');
      final r = await runTask(task);
      results.add(r);
      stdout.writeln(
        '  ${r.passed ? 'PASS' : 'FAIL'} in ${r.wallClock.inMilliseconds}ms'
        ' — ${r.checkerResults.where((c) => !c.passed).length} failing checks',
      );
      if (tracePath != null) {
        File(tracePath).writeAsStringSync(
          '${jsonEncode(r.toJson())}\n',
          mode: FileMode.append,
        );
      }
    }
    if (skipped > 0) {
      stdout.writeln('  ($skipped task(s) resumed from existing trace)');
    }
    return SuiteResult(results: results);
  }
}

/// Observability decorator: counts generations that came back with an error
/// so failure-mode classification can distinguish backend flakiness from
/// model-quality failures. Retry policy is untouched.
class _ErrorCountingHandler implements GenerationHandler {
  _ErrorCountingHandler(this.inner, this.onError);
  final GenerationHandler inner;
  final void Function() onError;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = await inner.generate(world, request);
    if (response.error.isNotEmpty) onError();
    return response;
  }
}
