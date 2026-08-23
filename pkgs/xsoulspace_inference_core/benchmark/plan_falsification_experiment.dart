// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 falsifying experiment — "goals as vectors, plans as projections".
///
/// Question (verbatim from the ADR): take one coding-suite task, express its
/// steps with checker-based success criteria, run the loop where mechanical
/// steps skip the LLM entirely, and measure the tokens/task delta. If the
/// delta is noise, the idea dies cheaply.
///
/// Two arms, identical task fixtures, identical canned model behavior (same
/// writes), same deterministic checkers:
///
/// - **baseline**: current harness path. Every tool-result triggers a ReAct
///   continuation decision (ADR 0005), so the model is called once more than
///   it has actions — the last call exists only to produce a narrative close.
/// - **plan-driven**: goal criteria live in the graph as a Goal + step
///   entities; a mechanical frontier policy evaluates the success predicates
///   itself when a tool result lands. Verified goal ⇒ no continuation decision
///   ⇒ the loop idles without ever asking the model whether it finished.
///   Failed predicates open ONE tight continuation (mechanical checker
///   feedback, same information budget as the suite's verifier loop).
///
/// Known deviation from the full ADR 0009 design: the frontier policy here
/// reads the jail filesystem directly. In the real design predicates run as
/// verifier tools behind seam 3 and their results become beats, keeping the
/// policy pure. This shortcut is acceptable for measuring the token delta;
/// it is NOT the production shape.
///
/// Run: `dart run benchmark/plan_falsification_experiment.dart`
library;

import 'dart:io';

import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'coding_suite/checkers.dart';
import 'coding_suite/runner.dart';
import 'coding_suite/scripted_handler.dart';
import 'coding_suite/task_spec.dart';

/// Experiment-local step status component (ADR 0009 §2 data shape preview).
class StepStatus implements Component {
  StepStatus(this.value);
  final String value; // open | verified | failed
}

/// Experiment-local backlink: which goal entity this step serves.
class StepGoalLink implements Component {
  const StepGoalLink(this.goal);
  final Entity goal;
}

/// The plan-frontier policy: fires exactly where [ReActContinuationPolicy]
/// fires (fresh tool result), but consults the GOAL first.
///
/// - All success criteria hold  → abstain (no agency; the loop goes idle).
/// - Any criterion fails        → open ONE tight continuation carrying the
///   failing predicate details (mechanical feedback, not narrative).
///
/// Deviation documented in the header: reads the jail fs directly instead of
/// consuming verifier-tool beats.
class PlanFrontierPolicy implements DecisionPolicy {
  PlanFrontierPolicy({required this.jailPath, required this.checkers});

  final String jailPath;
  final List<CheckerSpec> checkers;

  @override
  String get name => 'plan_frontier';

  @override
  DecisionDraft? evaluate(DecisionContext ctx) {
    if (!ctx.has<ToolResultPendingMarker>()) return null;

    final results = [
      for (final c in checkers) evaluateChecker(c, jailPath),
    ];
    final allPassed =
        results.isNotEmpty && results.every((r) => r.passed);

    // Flip step statuses in the graph (mechanical bookkeeping).
    _updateStepEntities(ctx.world, allPassed);

    if (allPassed) {
      // Goal vector satisfied — mechanically done. No LLM call is spent on
      // asking the model whether it finished. This is the entire bet.
      return null;
    }
    final failures = [
      for (final (i, r) in results.indexed)
        if (!r.passed) 'criterion #$i: ${r.detail}',
    ].join('\n');
    return DecisionDraft(
      prompt: 'Goal not yet verified. Failing criteria:\n$failures\n'
          'Continue working toward the goal.',
    );
  }

  void _updateStepEntities(World world, bool allPassed) {
    for (final (entity, _, _) in world.query2<StepGoalLink, StepStatus>()
        .toList()) {
      entity.insert(StepStatus(allPassed ? 'verified' : 'failed'));
    }
  }
}

/// Emits exactly one canned action per generation call — unlike
/// [ScriptedSuiteHandler] which dumps every step plus a narrative close in
/// one call. Mirrors how a real model behaves across continuation rounds.
class OneActionPerCallHandler implements GenerationHandler {
  OneActionPerCallHandler({required this.taskId});
  final String taskId;
  int _next = 0;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final steps = scriptedBehaviors[taskId]!;
    if (_next < steps.length) {
      final step = steps[_next++];
      final response = ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: {'text': 'step $_next'},
        rawOutput: 'step $_next',
        toolCalls: [
          ToolCall(name: ToolName(step.toolName), arguments: step.arguments),
        ],
        taskId: request.taskId,
      );
      world.events.writer<ActorGenerateResponse>().send(response);
      return response;
    }
    // All actions spent; nothing left to decide. (In the plan-driven arm the
    // frontier policy normally terminates the loop before this is reached.)
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'done'},
      rawOutput: 'done',
      taskId: request.taskId,
    );
  }
}

/// Plan-driven arm: mirrors CodingSuiteRunner.runTask's production world
/// construction, swaps the decision flow, adds Goal+step entities.
Future<_Row> _runPlanDriven(CodingTask task) async {
  final jail = await Directory.systemTemp.createTemp('plan_exp_${task.id}_');
  try {
    for (final f in task.fixtures) {
      final file = File('${jail.path}/${f.path}');
      await file.parent.create(recursive: true);
      await file.writeAsString(f.content);
    }

    final world = World()..addPlugin(AgentPlugin());
    final router = ModelRouter(inferenceClientsBuilders: {});
    final modelId = ModelId('suite-model');
    router.models[modelId] = Model(id: modelId, name: DefaultModelNames.appleFoundation);
    world
      ..upsertResource(ModelRouterResource(router))
      ..upsertResource(ToolRegistryResource())
      ..upsertResource(AgencyPolicy(maxConcurrent: 1))
      ..flush();

    world.getResource<GenerationHandlerResource>().registerDefault(
          OneActionPerCallHandler(taskId: task.id),
        );

    final registry = ToolRegistry();
    fsTools(FsToolsRoot(jail.path)).forEach(registry.register);
    world.getResource<ToolRegistryResource>().register('default', registry);

    // Replace the default ReAct flow with the plan frontier (ADR 0009 §3).
    world.upsertResource(
      DecisionFlowResource(
        DecisionFlow([
          PlanFrontierPolicy(jailPath: jail.path, checkers: task.checkers),
        ]),
      ),
    );

    final scene = world.spawnComponents([const Scene(), SceneFrame()]);
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

    // Goal vector + step entity — durable facts in the graph (ADR 0009 §1–2).
    final goal = world.spawnComponents([
      Goal(text: task.prompt),
    ]);
    world.spawnComponents([
      StepGoalLink(goal),
      StepStatus('open'),
    ]);
    world.flush();

    final responsesAtStart = world.events.hasRegistered<ActorGenerateResponse>()
        ? world.events.stats<ActorGenerateResponse>().sent
        : 0;

    final sw = Stopwatch()..start();
    final loop = HarnessLoop(world: world);
    await loop.runUntilIdle(maxTicks: 2000);
    sw.stop();

    var verifications = 0;
    // Count mechanical verifications: one per tool result that landed while
    // the frontier policy was active (each triggered a predicate evaluation
    // that never touched an LLM).
    for (final _ in world.query3<ToolResultContent, BeatStatus, TextContent>()) {
      verifications++;
    }

    final llmCalls =
        world.events.stats<ActorGenerateResponse>().sent - responsesAtStart;
    var tokensUsed = 0;
    for (final (_, _, situation) in world.query2<Actor, Situation>()) {
      tokensUsed += situation.tokensUsed;
    }

    final checkerResults = [
      for (final c in task.checkers) evaluateChecker(c, jail.path),
    ];
    final passed =
        checkerResults.isNotEmpty && checkerResults.every((c) => c.passed);

    return _Row(
      taskId: task.id,
      passed: passed,
      llmCalls: llmCalls,
      tokensUsed: tokensUsed,
      wallMs: sw.elapsedMilliseconds,
      mechanicalVerifications: verifications,
      stepStatuses: [
        for (final (_, _, s) in world.query2<StepGoalLink, StepStatus>()) s.value,
      ],
    );
  } finally {
    jail.delete(recursive: true);
  }
}

class _Row {
  _Row({
    required this.taskId,
    required this.passed,
    required this.llmCalls,
    required this.tokensUsed,
    required this.wallMs,
    required this.mechanicalVerifications,
    required this.stepStatuses,
  });
  final String taskId;
  final bool passed;
  final int llmCalls;
  final int tokensUsed;
  final int wallMs;
  final int mechanicalVerifications;
  final List<String> stepStatuses;
}

Future<void> main(List<String> args) async {
  final filter = args.isEmpty ? '' : args.first;
  final tasks = loadTasks('benchmark/coding_suite/tasks')
      .where((t) => t.id.contains(filter))
      .toList();
  stdout.writeln('ADR 0009 falsifying experiment — ${tasks.length} tasks\n');

  // Arm A: baseline through the untouched production runner.
  final baseline = await CodingSuiteRunner(
    buildHandler: (task) => ScriptedSuiteHandler(taskId: task.id),
    maxCheckerRetries: 0,
    backendLabel: 'exp-baseline',
    modelLabel: 'scripted',
  ).runAll(tasks);

  // Arm B: plan-driven.
  final planRows = <_Row>[];
  for (final task in tasks) {
    planRows.add(await _runPlanDriven(task));
  }

  // Comparison table.
  final b = StringBuffer()
    ..writeln('| task | base calls | plan calls | base tokens | plan tokens |'
        ' token Δ | mech verifies | pass |')
    ..writeln('|---|---|---|---|---|---|---|---|');
  var baseTok = 0, planTok = 0, baseCalls = 0, planCalls = 0;
  var allPass = true;
  for (var i = 0; i < tasks.length; i++) {
    final br = baseline.results[i];
    final pr = planRows[i];
    allPass &= pr.passed && br.passed;
    baseTok += br.tokensUsed;
    planTok += pr.tokensUsed;
    baseCalls += br.llmCalls;
    planCalls += pr.llmCalls;
    final delta = br.tokensUsed == 0
        ? 0
        : ((pr.tokensUsed - br.tokensUsed) / br.tokensUsed * 100);
    b.writeln(
      '| ${br.taskId} | ${br.llmCalls} | ${pr.llmCalls} '
      '| ${br.tokensUsed} | ${pr.tokensUsed} | ${delta.toStringAsFixed(0)}% '
      '| ${pr.mechanicalVerifications} '
      '| ${(br.passed && pr.passed) ? '✅' : '❌'} |',
    );
  }
  b..writeln('')
    ..writeln('**Totals** — calls: $baseCalls → $planCalls '
        '(${((planCalls - baseCalls) / (baseCalls == 0 ? 1 : baseCalls) * 100).toStringAsFixed(0)}%), '
        'tokens: $baseTok → $planTok '
        '(${((planTok - baseTok) / (baseTok == 0 ? 1 : baseTok) * 100).toStringAsFixed(0)}%)')
    ..writeln()
    ..writeln(allPass
        ? 'Both arms pass all checkers — comparison is valid.'
        : '⚠️ some tasks failed — comparison invalid, fix before reading deltas.');

  stdout.writeln(b);
  exit(0);
}
