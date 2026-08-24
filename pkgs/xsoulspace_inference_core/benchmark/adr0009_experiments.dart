// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 experiments — plan frontier, decomposition, idle-verify proof.
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
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'coding_suite/checkers.dart';
import 'coding_suite/scripted_handler.dart';
import 'coding_suite/task_spec.dart';
import 'shared/world_builder.dart';

// =============================================================================
// Falsification mode
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

// ---- Frontier policy ---------------------------------------------------------

/// The plan-frontier policy: fires exactly where [ReActContinuationPolicy]
/// fires (fresh tool result), but consults [GoalVerified] first — pure graph
/// logic, never I/O.
class PlanFrontierPolicy implements DecisionPolicy {
  PlanFrontierPolicy();

  @override
  String get name => 'plan_frontier';

  @override
  DecisionDraft? evaluate(DecisionContext ctx) {
    if (!ctx.has<ToolResultPendingMarker>()) return null;
    final verified = ctx.get<GoalVerified>();
    if (verified == null) return null;
    _updateStepStatuses(ctx.world, verified.passed);
    if (verified.passed) return null;
    return DecisionDraft(
      prompt: 'Goal not yet verified. Failing criteria:\n${verified.detail}\n'
          'Continue working toward the goal.',
    );
  }
}

void _updateStepStatuses(World world, bool allPassed) {
  for (final (entity, _, _) in world
      .query2<StepGoalLink, StepStatus>()
      .toList()) {
    entity.insert(StepStatus(allPassed ? 'verified' : 'failed'));
  }
}

/// Mechanical verification: runs after tool results land, executes the
/// registered `verify_workspace` tool through the executor path, stamps
/// [GoalVerified]. Never calls a model.
Future<void> goalVerificationSystem(World world) async {
  for (final _ in world.query2<Actor, ToolResultPendingMarker>().toList()) {
    final verify =
        world.getResource<ToolExecutorResource>().get(const ToolName('verify_workspace'));
    final output = await verify?.call({});
    Object? decoded = output;
    if (decoded is String) {
      try { decoded = jsonDecode(decoded); } catch (_) {}
    }
    var passed = false;
    var detail = '';
    if (decoded is Map) {
      passed = decoded['passed'] == true;
      detail = '${decoded['failures'] ?? ''}';
    } else {
      detail = 'verify unavailable';
    }
    // Stamp GoalVerified onto every actor with an open decision context.
    for (final (actor, _, _) in world.query2<Actor, ActorGoalRef>().toList()) {
      actor.insert(GoalVerified(passed: passed, detail: detail));
    }
  }
  world.flush();
}

Future<PlanRow> runPlanArm(
  CodingTask task, {
  required bool planFrontier,
  required GenerationHandler Function(CodingTask task) buildHandler,
  int maxTicks = 2000,
) async {
  final built = await buildExperimentWorld(task, buildHandler: () => buildHandler(task));
  final world = built.world;
  final jail = built.jail;
  try {
    registerFsTools(world, jail);
    if (planFrontier) {
      final registry = ToolRegistry();
      fsTools(FsToolsRoot(jail.path)).forEach(registry.register);
      registry.register(
        ToolDef.encode(
          name: const ToolName('verify_workspace'),
          description: 'Evaluate goal success criteria against workspace.',
          execute: (args) async {
            final results = [for (final c in task.checkers) evaluateChecker(c, jail.path)];
            return {
              'passed': results.isNotEmpty && results.every((r) => r.passed),
              'failures': [
                for (final (i, r) in results.indexed)
                  if (!r.passed) 'criterion #$i: ${r.detail}',
              ].join('\n'),
            };
          },
        ),
      );
      world.getResource<ToolRegistryResource>().register('default', registry);
      world.schedule(Schedules.narrative).add(goalVerificationSystem, name: 'goalVerification');
      world.upsertResource(DecisionFlowResource(DecisionFlow([PlanFrontierPolicy()])));
    }

    final actor = spawnStandardActor(world, systemPrompt: task.systemPrompt, prompt: task.prompt);
    final goal = world.spawnComponents([Goal(text: task.prompt)]);
    world.spawnComponents([StepGoalLink(goal), StepStatus('open')]);
    world.upsertComponent(actor, ActorGoalRef(goal));
    world.flush();

    final start = responseCount(world);
    final sw = Stopwatch()..start();
    await HarnessLoop(world: world).runUntilIdle(maxTicks: maxTicks);
    sw.stop();

    var verifications = 0;
    for (final _ in world.query3<ToolResultContent, BeatStatus, TextContent>()) {
      verifications++;
    }
    final llmCalls = responseCount(world) - start;
    var tokensUsed = 0;
    for (final (_, _, situation) in world.query2<Actor, Situation>()) {
      tokensUsed += situation.tokensUsed;
    }
    final toolErrors = <String>{};
    for (final (_, content, _) in world.query2<ToolResultContent, BeatStatus>().toList()) {
      final out = content.output.toString();
      if (out.contains('"error"')) toolErrors.add(out);
    }
    return PlanRow(
      taskId: task.id,
      passed: checkTask(task, jail),
      llmCalls: llmCalls,
      tokensUsed: tokensUsed,
      wallMs: sw.elapsedMilliseconds,
      mechanicalVerifications: planFrontier ? verifications : 0,
      cumulativeTokens: built.tokenTotal[0],
      toolErrors: toolErrors.toList(),
      stepStatuses: [
        for (final (_, _, s) in world.query2<StepGoalLink, StepStatus>()) s.value,
      ],
    );
  } finally {
    jail.delete(recursive: true);
  }
}

Future<void> _runFalsification(List<String> args) async {
  final filter = args.isEmpty ? '' : args.first;
  final tasks = loadTasks('benchmark/coding_suite/tasks')
      .where((t) => t.id.contains(filter))
      .toList();
  stdout.writeln('ADR 0009 falsification — ${tasks.length} tasks\n');

  final baseline = <PlanRow>[];
  final planRows = <PlanRow>[];
  for (final task in tasks) {
    baseline.add(await runPlanArm(
      task, planFrontier: false,
      buildHandler: (t) => OneActionPerCallHandler(taskId: t.id),
    ));
    planRows.add(await runPlanArm(
      task, planFrontier: true,
      buildHandler: (t) => OneActionPerCallHandler(taskId: t.id),
    ));
  }

  final b = StringBuffer()
    ..writeln('| task | base calls | plan calls | base tokens | plan tokens | token Δ | mech verifies | pass |')
    ..writeln('|---|---|---|---|---|---|---|---|');
  var baseTok = 0, planTok = 0, baseCalls = 0, planCalls = 0;
  var allPass = true;
  for (var i = 0; i < tasks.length; i++) {
    final br = baseline[i];
    final pr = planRows[i];
    allPass &= pr.passed && br.passed;
    baseTok += br.tokensUsed; planTok += pr.tokensUsed;
    baseCalls += br.llmCalls; planCalls += pr.llmCalls;
    final delta = br.tokensUsed == 0 ? 0 : ((pr.tokensUsed - br.tokensUsed) / br.tokensUsed * 100);
    b.writeln('| ${br.taskId} | ${br.llmCalls} | ${pr.llmCalls} '
        '| ${br.tokensUsed} | ${pr.tokensUsed} | ${delta.toStringAsFixed(0)}% '
        '| ${pr.mechanicalVerifications} | ${(br.passed && pr.passed) ? '✅' : '❌'} |');
  }
  b..writeln('')
    ..writeln('**Totals** — calls: $baseCalls → $planCalls '
        '(${((planCalls - baseCalls) / (baseCalls == 0 ? 1 : baseCalls) * 100).toStringAsFixed(0)}%), '
        'tokens: $baseTok → $planTok '
        '(${((planTok - baseTok) / (baseTok == 0 ? 1 : baseTok) * 100).toStringAsFixed(0)}%)')
    ..writeln()
    ..writeln(allPass
        ? 'Both arms pass all checkers — comparison is valid.'
        : '⚠️ some tasks failed — comparison invalid.');
  stdout.writeln(b);
}

// =============================================================================
// Idle-proof mode
// =============================================================================

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
        toolCalls: [ToolCall(name: ToolName(step.toolName), arguments: step.arguments)],
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

Future<void> _runIdleProof() async {
  final tasks = loadTasks('benchmark/coding_suite/tasks')
      .where((t) => t.id == 'edit_01_rename_constant')
      .toList();
  final row = await runPlanArm(
    tasks.first,
    planFrontier: true,
    buildHandler: (t) => FlakyAnswerFirstHandler(taskId: t.id),
  );
  stdout.writeln('calls=${row.llmCalls} passed=${row.passed} cumTokens=${row.cumulativeTokens}');
  final ok = row.passed && row.llmCalls == 2;
  stdout.writeln(ok
      ? '✅ idle-verify rule works.'
      : '❌ rule did not behave as designed.');
  exit(ok ? 0 : 1);
}

// =============================================================================
// Decomposition mode
// =============================================================================

/// Emits the FIRST OPEN step's action per call.
class StepExecutorHandler implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    StepAction? currentAction;
    for (final (entity, _, status)
        in world.query2<ActorGoalRef, StepStatus>().toList()) {
      if (status.value == 'open') {
        currentAction = entity.get<StepAction>();
        break;
      }
    }
    if (currentAction == null) {
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: const {'text': 'done'},
        rawOutput: 'done',
        taskId: request.taskId,
      );
    }
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'executing step'},
      rawOutput: 'executing step',
      toolCalls: [
        ToolCall(name: ToolName(currentAction.toolName), arguments: currentAction.arguments),
      ],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// After each tool result: verify the executed step, flip status, open next
/// step's decision — or terminate when all steps are verified.
Future<void> stepFrontierSystem(World world) async {
  for (final _ in world.query2<Actor, ToolResultPendingMarker>().toList()) {
    for (final (stepEntity, _, status)
        in world.query2<StepGoalLink, StepStatus>().toList()) {
      if (status.value != 'open') continue;
      final claim = stepEntity.get<StepClaim>()!;
      final action = stepEntity.get<StepAction>()!;
      final index = stepEntity.get<StepIndex>()!.value;

      final verify =
          world.getResource<ToolExecutorResource>().get(const ToolName('verify_step'));
      var passed = false;
      var detail = '';
      final output = await verify?.call(action.arguments);
      Object? decoded = output;
      if (decoded is String) { try { decoded = jsonDecode(decoded); } catch (_) {} }
      if (decoded is Map) {
        passed = decoded['passed'] == true;
        detail = '${decoded['failures'] ?? ''}';
      } else {
        detail = 'verify_step unavailable';
      }

      stepEntity.insert(StepStatus(passed ? 'verified' : 'failed'));
      stdout.writeln('[step $index] ${passed ? '✅ ${claim.text}' : '⚠️ retry: $detail'}');

      if (!passed) break;
      String? next;
      for (final (e2, _, s2) in world.query2<StepGoalLink, StepStatus>().toList()) {
        final i2 = e2.get<StepIndex>()!.value;
        if (s2.value == 'open' && i2 > index) {
          next = e2.get<StepClaim>()!.text;
          break;
        }
      }
      if (next != null) {
        for (final (actorEntity, _, _) in world.query2<Actor, ActorGoalRef>().toList()) {
          if (!actorEntity.has<OpenDecision>()) {
            actorEntity.insert(OpenDecision(prompt: 'Next step: $next\nPerform exactly this step.'));
          }
          break;
        }
      }
      break;
    }
  }
  world.flush();
}

void registerStepVerifier(
  ToolRegistry registry,
  ToolExecutorResource executors,
  Directory jail,
) {
  final def = ToolDef.encode(
    name: const ToolName('verify_step'),
    description: 'Verify one planned file-write step against the workspace.',
    execute: (args) async {
      final argMap = args is Map ? args : const {};
      final path = argMap['path'] as String?;
      final content = argMap['content'] as String?;
      if (path == null || content == null) {
        return {'passed': false, 'failures': 'path and content are required'};
      }
      final target = '${jail.path}/$path';
      final passed = File(target).existsSync() &&
          File(target).readAsStringSync() == content;
      return {'passed': passed, 'failures': passed ? '' : 'file $path content mismatch'};
    },
  );
  registry.register(def);
  executors.register(def.name, (args) => def.execute(args));
}

List<(StepClaim, StepAction)> decompose(CodingTask task) => [
      for (final s in scriptedBehaviors[task.id]!)
        (
          StepClaim('write ${s.arguments['path']}'),
          StepAction(s.toolName, s.arguments),
        ),
    ];

Future<void> _runDecomposition(List<String> args) async {
  final filter = args.isEmpty ? 'refactor_01' : args.first;
  final tasks = loadTasks('benchmark/coding_suite/tasks')
      .where((t) => t.id.contains(filter))
      .toList();

  final b = StringBuffer()
    ..writeln('| task | base calls | decomp calls | base cum | decomp cum | cum Δ | pass |')
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
        : ((dBuilt.tokenTotal[0] - baseBuilt.tokenTotal[0]) / baseBuilt.tokenTotal[0] * 100);
    b.writeln('| ${task.id} | $baseCalls | $dCalls '
        '| ${baseBuilt.tokenTotal[0]} | ${dBuilt.tokenTotal[0]} | ${delta.toStringAsFixed(0)}% '
        '| ${(basePassed && dPassed) ? '✅' : '❌'} |');
    await baseBuilt.jail.delete(recursive: true);
    await dBuilt.jail.delete(recursive: true);
  }

  b..writeln()
    ..writeln(allPass ? '✅ both shapes pass all checkers.' : '⚠️ failures present.');
  stdout.writeln(b);
}

Future<({World world, Directory jail, List<int> tokenTotal})>
    _buildDecompWorld(CodingTask task, {required bool monolithic}) async {
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
  registerStepVerifier(registry, world.getResource<ToolExecutorResource>(), jail);
  if (!monolithic) {
    world.upsertResource(DecisionFlowResource(DecisionFlow(const [])));
    world.schedule(Schedules.narrative).add(stepFrontierSystem, name: 'stepFrontier');
  }
  world.getResource<ToolRegistryResource>().register('default', registry);

  spawnStandardActor(world, systemPrompt: task.systemPrompt, prompt: task.prompt);
  if (!monolithic) {
    final goal = world.spawnComponents([Goal(text: task.prompt)]);
    final actor = world.query2<Actor, ActorGoalRef>().isEmpty
        ? null
        : world.query2<Actor, ActorGoalRef>().first.$1;
    if (actor != null) world.upsertComponent(actor.entity, ActorGoalRef(goal));
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
      stderr.writeln('Unknown mode "$mode". Use: falsification | decomposition | idle-proof');
      exit(64);
  }
}
