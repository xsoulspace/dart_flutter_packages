// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 experiments CLI — plan frontier, decomposition, idle-verify proof
/// against SCRIPTED handlers (no LLM required).
///
/// Consolidates three former entry points into one CLI:
///
/// ```
/// dart run benchmark/adr0009_experiments.dart --mode falsification [filter]
/// dart run benchmark/adr0009_experiments.dart --mode decomposition [filter]
/// dart run benchmark/adr0009_experiments.dart --mode idle-proof
/// ```
///
/// - **falsification**: baseline ReAct vs mechanical plan-frontier on every
///   coding-suite task; measures calls + tokens/task delta.
/// - **decomposition**: monolithic vs per-step acceptance criteria; measures
///   whether tighter in-frame cuts reduce spend.
/// - **idle-proof**: deterministic proof that "idle + open goal ⇒ verify"
///   catches answer-without-acting flakes at bounded cost.
///
/// The arms themselves live in `experiment_arms.dart` so real-model probe
/// bins can inject a [GenerationHandler] factory; this file owns only the
/// scripted handlers and CLI wiring.
library;

import 'dart:io';

import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'coding_suite/scripted_handler.dart';
import 'coding_suite/task_spec.dart';
import 'experiment_arms.dart';
import 'shared/world_builder.dart';

// =============================================================================
// Scripted handlers
// =============================================================================

/// Emits exactly one canned action per generation call.
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
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'done'},
      rawOutput: 'done',
      taskId: request.taskId,
    );
  }
}

/// Answers without acting on call #1; performs the real edit afterwards.
class FlakyAnswerFirstHandler implements GenerationHandler {
  FlakyAnswerFirstHandler({required this.taskId});
  final String taskId;
  var _callCount = 0;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    _callCount++;
    if (_callCount == 1) {
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: const {'text': 'Done! I renamed the constant.'},
        rawOutput: 'Done! I renamed the constant.',
        taskId: request.taskId,
      );
    }
    final steps = scriptedBehaviors[taskId]!;
    final idx = _callCount - 2;
    if (idx >= 0 && idx < steps.length) {
      final step = steps[idx];
      final response = ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: {'text': 'step $_callCount'},
        rawOutput: 'step $_callCount',
        toolCalls: [
          ToolCall(name: ToolName(step.toolName), arguments: step.arguments),
        ],
        taskId: request.taskId,
      );
      world.events.writer<ActorGenerateResponse>().send(response);
      return response;
    }
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'done'},
      rawOutput: 'done',
      taskId: request.taskId,
    );
  }
}

// =============================================================================
// Scripted decomposition world builder
// =============================================================================

Future<({World world, Directory jail, List<int> tokenTotal})> _buildDecompWorld(
  CodingTask task, {
  required bool monolithic,
}) async {
  final built = await buildExperimentWorld(
    task,
    buildHandler: () => monolithic
        ? ScriptedSuiteHandler(taskId: task.id)
        : StepExecutorHandler(),
  );
  final world = built.world;
  final jail = built.jail;
  final registry = ToolRegistry();
  fsTools(FsToolsRoot(jail.path)).forEach(registry.register);
  registerStepVerifier(
    registry,
    world.getResource<ToolExecutorResource>(),
    jail,
  );
  world.upsertResource(StepFrontierConfig());
  if (!monolithic) {
    world.upsertResource(DecisionFlowResource(DecisionFlow(const [])));
    world
        .schedule(Schedules.narrative)
        .add(stepFrontierSystem, name: 'stepFrontier');
  }
  world.getResource<ToolRegistryResource>().register('default', registry);

  final actor = spawnStandardActor(
    world,
    systemPrompt: task.systemPrompt,
    prompt: task.prompt,
  );
  if (!monolithic) {
    final goal = world.spawnComponents([Goal(text: task.prompt)]);
    world.upsertComponent(actor, ActorGoalRef(goal));
    for (final (i, step) in decompose(task).indexed) {
      world.spawnComponents([
        StepGoalLink(goal),
        StepStatus('open'),
        step.$1,
        step.$2,
        StepIndex(i),
      ]);
    }
  }
  world.flush();
  return built;
}

Future<void> _runDecomposition(List<String> args) async {
  final filter = args.isEmpty ? 'refactor_01' : args.first;
  final tasks = loadTasks(
    'benchmark/coding_suite/tasks',
  ).where((t) => t.id.contains(filter)).toList();

  final b = StringBuffer()
    ..writeln(
      '| task | base calls | decomp calls | base cum | decomp cum | cum Δ | pass |',
    )
    ..writeln('|---|---|---|---|---|---|---|');
  var allPass = true;

  for (final task in tasks) {
    final baseBuilt = await _buildDecompWorld(task, monolithic: true);
    final baseStart = responseCount(baseBuilt.world);
    await HarnessLoop(world: baseBuilt.world).runUntilIdle(maxTicks: 2000000);
    final baseCalls = responseCount(baseBuilt.world) - baseStart;
    final basePassed = checkTask(task, baseBuilt.jail);

    final dBuilt = await _buildDecompWorld(task, monolithic: false);
    final dStart = responseCount(dBuilt.world);
    await HarnessLoop(world: dBuilt.world).runUntilIdle(maxTicks: 2000000);
    final dCalls = responseCount(dBuilt.world) - dStart;
    final dPassed = checkTask(task, dBuilt.jail);

    allPass &= basePassed && dPassed;
    final delta = baseBuilt.tokenTotal[0] == 0
        ? 0
        : ((dBuilt.tokenTotal[0] - baseBuilt.tokenTotal[0]) /
              baseBuilt.tokenTotal[0] *
              100);
    b.writeln(
      '| ${task.id} | $baseCalls | $dCalls '
      '| ${baseBuilt.tokenTotal[0]} | ${dBuilt.tokenTotal[0]} | ${delta.toStringAsFixed(0)}% '
      '| ${(basePassed && dPassed) ? '✅' : '❌'} |',
    );
    await baseBuilt.jail.delete(recursive: true);
    await dBuilt.jail.delete(recursive: true);
  }

  b
    ..writeln()
    ..writeln(
      allPass ? '✅ both shapes pass all checkers.' : '⚠️ failures present.',
    );
  stdout.writeln(b);
}

Future<void> _runFalsification(List<String> args) async {
  final filter = args.isEmpty ? '' : args.first;
  final tasks = loadTasks(
    'benchmark/coding_suite/tasks',
  ).where((t) => t.id.contains(filter)).toList();
  stdout.writeln('ADR 0009 falsification — ${tasks.length} tasks\n');

  final baseline = <PlanRow>[];
  final planRows = <PlanRow>[];
  for (final task in tasks) {
    baseline.add(
      await runPlanArm(
        task,
        planFrontier: false,
        buildHandler: (t) => OneActionPerCallHandler(taskId: t.id),
      ),
    );
    planRows.add(
      await runPlanArm(
        task,
        planFrontier: true,
        buildHandler: (t) => OneActionPerCallHandler(taskId: t.id),
      ),
    );
  }

  final b = StringBuffer()
    ..writeln(
      '| task | base calls | plan calls | base tokens | plan tokens | token Δ | mech verifies | pass |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|');
  var baseTok = 0, planTok = 0, baseCalls = 0, planCalls = 0;
  var allPass = true;
  for (var i = 0; i < tasks.length; i++) {
    final br = baseline[i];
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
      '| ${pr.mechanicalVerifications} | ${(br.passed && pr.passed) ? '✅' : '❌'} |',
    );
  }
  b
    ..writeln('')
    ..writeln(
      '**Totals** — calls: $baseCalls → $planCalls '
      '(${((planCalls - baseCalls) / (baseCalls == 0 ? 1 : baseCalls) * 100).toStringAsFixed(0)}%), '
      'tokens: $baseTok → $planTok '
      '(${((planTok - baseTok) / (baseTok == 0 ? 1 : baseTok) * 100).toStringAsFixed(0)}%)',
    )
    ..writeln()
    ..writeln(
      allPass
          ? 'Both arms pass all checkers — comparison is valid.'
          : '⚠️ some tasks failed — comparison invalid.',
    );
  stdout.writeln(b);
}

// =============================================================================
// Idle-proof mode
// =============================================================================

Future<void> _runIdleProof() async {
  final tasks = loadTasks(
    'benchmark/coding_suite/tasks',
  ).where((t) => t.id == 'edit_01_rename_constant').toList();
  final row = await runPlanArm(
    tasks.first,
    planFrontier: true,
    buildHandler: (t) => FlakyAnswerFirstHandler(taskId: t.id),
  );
  stdout.writeln(
    'calls=${row.llmCalls} passed=${row.passed} cumTokens=${row.cumulativeTokens}',
  );
  final ok = row.passed && row.llmCalls == 2;
  stdout.writeln(
    ok ? '✅ idle-verify rule works.' : '❌ rule did not behave as designed.',
  );
  exit(ok ? 0 : 1);
}

// =============================================================================
// CLI
// =============================================================================

Future<void> main(List<String> args) async {
  var mode = 'falsification';
  final rest = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--mode') {
      mode = args[++i];
    } else {
      rest.add(args[i]);
    }
  }
  switch (mode) {
    case 'falsification':
      await _runFalsification(rest);
    case 'decomposition':
      await _runDecomposition(rest);
    case 'idle-proof':
      await _runIdleProof();
    default:
      stderr.writeln(
        'Unknown mode "$mode". Use: falsification | decomposition | idle-proof',
      );
      exit(64);
  }
}
