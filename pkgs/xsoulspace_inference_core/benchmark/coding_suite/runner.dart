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
/// suite can be pointed at AFM (via AppleFoundationInferenceClient) or at pi
/// (via a local OpenAI-compatible shim) for apples-to-apples comparison.
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

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
    required this.llmCalls,
    required this.toolCalls,
  });

  final String taskId;
  final String category;
  final bool passed;
  final List<CheckerResult> checkerResults;
  final Duration wallClock;
  final int tokensUsed;
  final int llmCalls;
  final List<String> toolCalls;

  Map<String, Object?> toJson() => {
    'task_id': taskId,
    'category': category,
    'passed': passed,
    'wall_clock_ms': wallClock.inMilliseconds,
    'tokens_used': tokensUsed,
    'llm_calls': llmCalls,
    'tool_calls': toolCalls,
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
      ..writeln('')
      ..writeln(
        '**$label**: $passedCount/$total passed '
        '(${(passRate * 100).toStringAsFixed(0)}%), '
        '$totalTokens tokens total, '
        '${totalWallClock.inSeconds}s wall clock.',
      );
    return b.toString();
  }
}

/// Runs [CodingTask]s through the real harness loop.
class CodingSuiteRunner {
  CodingSuiteRunner({
    required this.buildHandler,
    this.jailParent,
    this.modelId = const ModelId('suite-model'),
    this.maxConcurrent = 1,
    this.maxCheckerRetries = 0,
    this.maxToolRounds = 16,
  });

  /// Builds the generation handler for each run (fresh per task so state
  /// never leaks between tasks). Receives the task so handlers can key
  /// behavior on [CodingTask.id].
  final GenerationHandler Function(CodingTask task) buildHandler;

  /// Parent directory for per-task jails. Defaults to a system temp dir.
  final Directory? jailParent;

  /// Model id registered in the router for the run's single model.
  final ModelId modelId;

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
      final router = ModelRouter(inferenceClientsBuilders: {});
      router.models[modelId] = Model(
        id: modelId,
        name: DefaultModelNames.appleFoundation,
      );
      world
        ..upsertResource(ModelRouterResource(router))
        ..upsertResource(ToolRegistryResource())
        ..upsertResource(AgencyPolicy(maxConcurrent: maxConcurrent, maxToolRounds: maxToolRounds))
        ..flush();

      final handler = buildHandler(task);
      world.getResource<GenerationHandlerResource>().registerDefault(handler);

      final registry = ToolRegistry();
      fsTools(FsToolsRoot(jail.path)).forEach(registry.register);
      world.getResource<ToolRegistryResource>().register('default', registry);

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      // Give the actor a thread BEFORE spawning so tool/assistant beats
      // attach to it (attachBeatToActorThread) and projection can ray-trace
      // the conversation into continuation decisions. Without this the model
      // continues blind after each tool result (mirrors world_setup.spawnActors).
      final actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: modelId),
        ActorSystemPrompt(text: task.systemPrompt),
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
      stdout.writeln(
        '  [debug] trc=${world.query<ToolResultContent>().length} '
        'bs=${world.query<BeatStatus>().length} '
        'tc=${world.query<TextContent>().length} '
        'toolCallEvtSent=${world.events.hasRegistered<ToolCallEvent>() ? world.events.stats<ToolCallEvent>().sent : 'n/a'} '
        'respSent=$responsesSent()',
      );
      for (final record
          in world.query3<ToolResultContent, BeatStatus, TextContent>()) {
        toolCalls.add(record.$2.name);
      }

      return TaskResult(
        taskId: task.id,
        category: task.category.yamlName,
        passed:
            checkerResults.isNotEmpty && checkerResults.every((c) => c.passed),
        checkerResults: checkerResults,
        wallClock: sw.elapsed,
        tokensUsed: tokensUsed,
        llmCalls: llmCalls,
        toolCalls: toolCalls,
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
    final results = <TaskResult>[];
    for (final task in selected) {
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
    return SuiteResult(results: results);
  }
}
