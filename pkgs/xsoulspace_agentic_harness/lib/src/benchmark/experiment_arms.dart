// ignore_for_file: lines_longer_than_80_chars

/// Injectable ADR 0009 experiment arms.
///
/// The arms behind `adr0009_experiments.dart`'s scripted CLI, exposed as
/// functions so real-model probe bins (AFM, OpenRouter) can run the identical
/// machinery with an injected [GenerationHandler] factory:
///
/// - [runPlanArm] — one task under ReAct baseline or plan-frontier close-out.
/// - [runDecomposedArmReal] — ONE guided decompose call → mechanical step
///   execution → per-step verification (LLM called exactly once + retries).
/// - [runPlanProbe] / [runDecompositionProbe] — per-suite loops that stamp
///   backend/model labels, append JSONL trace rows, and return markdown.
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import '../../xsoulspace_agentic_harness.dart';
import '../tools/fs_tools.dart';
import 'coding_suite/checkers.dart';
import 'coding_suite/scripted_handler.dart';
import 'coding_suite/task_spec.dart';

// =============================================================================
// Plan-frontier arm
// =============================================================================

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
      prompt:
          'Goal not yet verified. Failing criteria:\n${verified.detail}\n'
          'Continue working toward the goal.',
    );
  }
}

void _updateStepStatuses(World world, bool allPassed) {
  for (final (entity, _, _)
      in world.query2<StepGoalLink, StepStatus>().toList()) {
    entity.insert(StepStatus(allPassed ? 'verified' : 'failed'));
  }
}

/// Mechanical verification: runs after tool results land, executes the
/// registered `verify_workspace` tool through the executor path, stamps
/// [GoalVerified]. Never calls a model.
Future<void> goalVerificationSystem(World world) async {
  for (final _ in world.query2<Actor, ToolResultPendingMarker>().toList()) {
    final verify = world.getResource<ToolExecutorResource>().get(
      const ToolName('verify_workspace'),
    );
    final output = await verify?.call({});
    Object? decoded = output;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {}
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

/// Runs one task under either the ReAct baseline or the plan-frontier arm,
/// with the backend handler injected. Returns metrics in a [PlanRow].
Future<PlanRow> runPlanArm(
  CodingTask task, {
  required bool planFrontier,
  required GenerationHandler Function(CodingTask task) buildHandler,
  int maxTicks = 2000,
}) async {
  final built = await buildExperimentWorld(
    task,
    buildHandler: () => buildHandler(task),
  );
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
            final results = [
              for (final c in task.checkers) evaluateChecker(c, jail.path),
            ];
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
      world
          .schedule(Schedules.narrative)
          .add(goalVerificationSystem, name: 'goalVerification');
      world.upsertResource(
        DecisionFlowResource(DecisionFlow([PlanFrontierPolicy()])),
      );
    }

    final actor = spawnStandardActor(
      world,
      systemPrompt: task.systemPrompt,
      prompt: task.prompt,
    );
    final goal = world.spawnComponents([Goal(text: task.prompt)]);
    world.spawnComponents([StepGoalLink(goal), StepStatus('open')]);
    world.upsertComponent(actor, ActorGoalRef(goal));
    world.flush();

    final start = responseCount(world);
    final sw = Stopwatch()..start();
    await HarnessLoop(world: world).runUntilIdle(maxTicks: maxTicks);
    sw.stop();

    var verifications = 0;
    for (final _
        in world.query3<ToolResultContent, BeatStatus, TextContent>()) {
      verifications++;
    }
    final llmCalls = responseCount(world) - start;
    var tokensUsed = 0;
    for (final (_, _, situation) in world.query2<Actor, Situation>()) {
      tokensUsed += situation.tokensUsed;
    }
    final toolErrors = <String>{};
    for (final (_, content, _)
        in world.query2<ToolResultContent, BeatStatus>().toList()) {
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
        for (final (_, _, s) in world.query2<StepGoalLink, StepStatus>())
          s.value,
      ],
    );
  } finally {
    jail.delete(recursive: true);
  }
}

// =============================================================================
// Decomposition machinery
// =============================================================================

/// Whether [stepFrontierSystem] opens an LLM decision for the NEXT step.
/// True for the scripted decomposition CLI (the handler executes each step);
/// false for the real-model arm (steps execute MECHANICALLY from the
/// decompose plan — no further agency at all).
class StepFrontierConfig extends Resource {
  StepFrontierConfig({this.openNextDecisions = true});
  final bool openNextDecisions;
}

/// Emits the FIRST OPEN step's action per call. The model never decides what
/// to do next — the frontier already did; it only executes one step.
class StepExecutorHandler implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    StepAction? currentAction;
    for (final (entity, _, status)
        in world.query2<StepGoalLink, StepStatus>().toList()) {
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
        ToolCall(
          name: ToolName(currentAction.toolName),
          arguments: currentAction.arguments,
        ),
      ],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// After each tool result: verify the executed step, flip its status, and —
/// while [StepFrontierConfig.openNextDecisions] — open the next step's
/// decision on the actor. With the config off, termination is mechanical:
/// when the last open step is verified no decision remains.
Future<void> stepFrontierSystem(World world) async {
  final config = world.getResource<StepFrontierConfig>();
  for (final _ in world.query2<Actor, ToolResultPendingMarker>().toList()) {
    for (final (stepEntity, _, status)
        in world.query2<StepGoalLink, StepStatus>().toList()) {
      if (status.value != 'open') continue;
      final claim = stepEntity.get<StepClaim>()!;
      final action = stepEntity.get<StepAction>()!;
      final index = stepEntity.get<StepIndex>()!.value;

      final verify = world.getResource<ToolExecutorResource>().get(
        const ToolName('verify_step'),
      );
      var passed = false;
      var detail = '';
      final output = await verify?.call(action.arguments);
      Object? decoded = output;
      if (decoded is String) {
        try {
          decoded = jsonDecode(decoded);
        } catch (_) {}
      }
      if (decoded is Map) {
        passed = decoded['passed'] == true;
        detail = '${decoded['failures'] ?? ''}';
      } else {
        detail = 'verify_step unavailable';
      }

      stepEntity.insert(StepStatus(passed ? 'verified' : 'failed'));
      stdout.writeln(
        '[step $index] ${passed ? '✅ ${claim.text}' : '⚠️ retry: $detail'}',
      );

      if (!passed || !config.openNextDecisions) break;
      String? next;
      for (final (e2, _, s2)
          in world.query2<StepGoalLink, StepStatus>().toList()) {
        final i2 = e2.get<StepIndex>()!.value;
        if (s2.value == 'open' && i2 > index) {
          next = e2.get<StepClaim>()!.text;
          break;
        }
      }
      if (next != null) {
        for (final (actorEntity, _, _)
            in world.query2<Actor, ActorGoalRef>().toList()) {
          if (!actorEntity.has<OpenDecision>()) {
            actorEntity.insert(
              OpenDecision(
                prompt: 'Next step: $next\nPerform exactly this step.',
              ),
            );
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
      final passed =
          File(target).existsSync() &&
          File(target).readAsStringSync() == content;
      return {
        'passed': passed,
        'failures': passed ? '' : 'file $path content mismatch',
      };
    },
  );
  registry.register(def);
  executors.register(def.name, def.execute);
}

/// Decompose a task into steps derived from its canned behavior (the
/// decompose-once act, mocked): one write-step per scripted action, each
/// with an exact-content acceptance predicate.
List<(StepClaim, StepAction)> decompose(CodingTask task) => [
  for (final s in scriptedBehaviors[task.id]!)
    (
      StepClaim('write ${s.arguments['path']}'),
      StepAction(s.toolName, s.arguments),
    ),
];

// =============================================================================
// Real-model decomposed arm
// =============================================================================

/// Guided schema for the single decompose call.
final decomposeStepsSchema = SchemaBundle(
  root: FM.object(
    'decompose',
    properties: () => [
      FM.prop(
        'steps',
        FM.array(
          FM.object(
            'step',
            properties: () => [
              FM.prop('path', FM.string()),
              FM.prop('content', FM.string()),
            ],
          ),
          min: 1,
        ),
      ),
    ],
  ),
);

/// Draft captured from the decompose response, consumed by
/// [decomposeTransformSystem].
class DecomposeDraftResource extends Resource {
  DecomposeDraftResource();
  List<Map<String, dynamic>> steps = const [];
  bool get hasDraft => steps.isNotEmpty;
}

String decomposeInstruction(CodingTask task) =>
    'GOAL: ${task.prompt}\n\n'
    'Decompose this goal into an ordered list of file-write steps. For each '
    'step provide the workspace-relative "path" and the FULL final file '
    '"content". The harness will write and verify each step mechanically — '
    'plan completely and precisely.';

/// Consumes [DecomposeDraftResource]: spawns step entities from the captured
/// draft. Pure graph logic.
Future<void> decomposeTransformSystem(World world) async {
  final draftResource = world.getResource<DecomposeDraftResource>();
  if (!draftResource.hasDraft) return;
  Entity? goal;
  for (final (_, ref, _) in world.query2<ActorGoalRef, Actor>().toList()) {
    goal = ref.goal;
    break;
  }
  if (goal == null) return;
  for (var i = 0; i < draftResource.steps.length; i++) {
    final st = draftResource.steps[i];
    world.spawnComponents([
      StepGoalLink(goal),
      StepStatus('open'),
      StepClaim('write ${st['path']}'),
      StepAction('write', {'path': st['path'], 'content': st['content']}),
      StepIndex(i),
    ]);
  }
  draftResource.steps = const [];
}

/// Executes the first open step's write MECHANICALLY through the jailed
/// `write` tool (seam 3), emitting the result through the canonical
/// [ToolResultEvent] path so the beat/pending-marker machinery stays intact
/// for [stepFrontierSystem]. One write in flight at a time.
Future<void> mechanicalStepExecutorSystem(World world) async {
  for (final _ in world.query2<Actor, ToolResultPendingMarker>().toList()) {
    return;
  }
  StepAction? action;
  for (final (e, _, st) in world.query2<StepGoalLink, StepStatus>().toList()) {
    if (st.value == 'open') {
      action = e.get<StepAction>();
      break;
    }
  }
  if (action == null) return;
  final registry = world.getResource<ToolRegistryResource>().get('default');
  final toolDef = registry?.get(const ToolName('write'));
  if (toolDef == null) return;
  Entity? actorEntity;
  for (final (entity, _, _) in world.query2<Actor, ActorGoalRef>().toList()) {
    actorEntity = entity.entity;
    break;
  }
  if (actorEntity == null) return;
  final value = await toolDef.execute(action.arguments);
  world.events.writer<ToolResultEvent>().send(
    ToolResultEvent(
      actorEntity: actorEntity,
      result: ToolExecutionResult(
        name: 'write',
        output: value is String ? value : jsonEncode(value),
      ),
      callArgs: action.arguments,
    ),
  );
}

/// Handler wrapper: strips the registry on the FIRST (decompose) call so a
/// wrapping guided-decision handler doesn't shadow the decompose schema, then
/// captures the structured `steps` payload into [draft].
class DecomposeCaptureHandler implements GenerationHandler {
  DecomposeCaptureHandler(this.inner, this.draft);
  final GenerationHandler inner;
  final DecomposeDraftResource draft;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final isDecomposeCall = !draft.hasDraft && _stepsSpawned(world) == 0;
    final effective = isDecomposeCall ? _stripRegistry(request) : request;
    final response = await inner.generate(world, effective);
    if (isDecomposeCall) _capture(response.structuredOutput);
    return response;
  }

  void _capture(Map<String, dynamic> structured) {
    final payload = structured['decompose'] is Map
        ? structured['decompose'] as Map
        : structured;
    final steps = payload['steps'];
    if (steps is! List) return;
    draft.steps = [
      for (final s in steps)
        if (s is Map && s['path'] != null && s['content'] != null)
          {'path': '${s['path']}', 'content': '${s['content']}'},
    ];
  }

  static ActorGenerateRequest _stripRegistry(ActorGenerateRequest r) =>
      ActorGenerateRequest(
        actorEntity: r.actorEntity,
        agentId: r.agentId,
        modelId: r.modelId,
        prompt: r.prompt,
        systemPrompt: r.systemPrompt,
        contextFragments: r.contextFragments,
        schema: r.schema,
        toolRegistry: null,
        task: InferenceTask.nativelyStructuredText,
        taskId: r.taskId,
      );

  static int _stepsSpawned(World world) =>
      world.query2<StepGoalLink, StepStatus>().length;
}

/// Real-model decomposed arm: ONE guided decompose call → mechanical
/// execution of every planned step through the jailed write executor →
/// per-step verification → termination without further LLM calls.
Future<DecompRunResult> runDecomposedArmReal(
  CodingTask task, {
  required GenerationHandler Function(CodingTask task) buildInnerHandler,
  int maxTicks = 2000000,
}) async {
  final draft = DecomposeDraftResource();
  var llmCalls = 0;
  final built = await buildExperimentWorld(
    task,
    buildHandler: () {
      final inner = buildInnerHandler(task);
      return CountingHandler(
        DecomposeCaptureHandler(inner, draft),
        () => llmCalls++,
      );
    },
  );
  final world = built.world;
  final jail = built.jail;
  try {
    final registry = ToolRegistry();
    fsTools(FsToolsRoot(jail.path)).forEach(registry.register);
    registerStepVerifier(
      registry,
      world.getResource<ToolExecutorResource>(),
      jail,
    );
    world.getResource<ToolRegistryResource>().register('default', registry);

    // NO ReAct continuation: the only LLM call is the decompose call.
    world
      ..upsertResource(draft)
      ..upsertResource(DecisionFlowResource(const DecisionFlow([])))
      ..upsertResource(StepFrontierConfig(openNextDecisions: false))
      ..flush();

    world.schedule(Schedules.narrative)
      ..add(decomposeTransformSystem, name: 'decomposeTransform')
      ..then(mechanicalStepExecutorSystem, name: 'mechanicalExecute')
      ..then(stepFrontierSystem, name: 'stepFrontier');

    final actor = spawnStandardActor(
      world,
      systemPrompt: task.systemPrompt,
      prompt: decomposeInstruction(task),
      schema: decomposeStepsSchema,
    );
    final goal = world.spawnComponents([Goal(text: task.prompt)]);
    world.upsertComponent(actor, ActorGoalRef(goal));
    world.flush();

    await HarnessLoop(world: world).runUntilIdle(maxTicks: maxTicks);

    var stepsVerified = 0;
    for (final (_, _, st)
        in world.query2<StepGoalLink, StepStatus>().toList()) {
      if (st.value == 'verified') stepsVerified++;
    }
    final checkersPassed = checkTask(task, jail);
    String failureMode = '';
    if (!checkersPassed) {
      if (llmCalls == 0) {
        failureMode = 'no-llm';
      } else if (!draft.hasDraft && stepsVerified == 0) {
        failureMode = 'no-decompose';
      } else if (stepsVerified == 0) {
        failureMode = 'no-steps-executed';
      } else {
        failureMode = 'wrong-content';
      }
    }

    return DecompRunResult(
      passed: checkersPassed,
      llmCalls: llmCalls,
      cumulativeTokens: built.tokenTotal[0],
      stepsVerified: stepsVerified,
      failureMode: failureMode,
    );
  } finally {
    jail.delete(recursive: true);
  }
}

// =============================================================================
// Probe suites (real-model loops shared by provider bins)
// =============================================================================

/// Runs the plan-frontier falsification pair per task (ReAct baseline vs
/// plan-frontier) with any injected backend, appends JSONL trace rows to
/// [tracePath] when given, and returns the markdown comparison table.
///
/// [arms] selects 'baseline' | 'plan' | 'both'. Role-tag state is read from
/// [ContextFragmentProtocol.roleTagsEnabled] (the host bin owns the flag).
Future<String> runPlanProbe(
  List<CodingTask> tasks, {
  required GenerationHandler Function(CodingTask task) buildHandler,
  String? tracePath,
  String arms = 'both',
  String backendLabel = 'scripted',
  String modelLabel = 'scripted',
  int maxTicks = 2000000,
}) async {
  stdout.writeln(
    'ADR 0009 real-model probe ($backendLabel:$modelLabel) — '
    '${tasks.length} tasks\n',
  );

  final rows = <(PlanRow?, PlanRow?)>[];
  for (final task in tasks) {
    stdout.writeln('▶ ${task.id}');
    PlanRow? baseline;
    PlanRow? plan;
    if (arms != 'plan') {
      baseline = await runPlanArm(
        task,
        planFrontier: false,
        buildHandler: buildHandler,
        maxTicks: maxTicks,
      );
      stdout.writeln(
        '  baseline: ${baseline.passed ? "PASS" : "FAIL"} — '
        '${baseline.llmCalls} calls, '
        'cum ${baseline.cumulativeTokens} tokens',
      );
    }
    if (arms != 'baseline') {
      plan = await runPlanArm(
        task,
        planFrontier: true,
        buildHandler: buildHandler,
        maxTicks: maxTicks,
      );
      stdout.writeln(
        '  plan:     ${plan.passed ? "PASS" : "FAIL"} — '
        '${plan.llmCalls} calls, cum ${plan.cumulativeTokens} tokens',
      );
    }
    rows.add((baseline, plan));
  }

  final tagLabel = ContextFragmentProtocol.roleTagsEnabled
      ? 'tags-on'
      : 'tags-OFF';
  final b = StringBuffer()
    ..writeln()
    ..writeln('(role tags: $tagLabel)')
    ..writeln(
      '| task | base calls | plan calls | base cum tokens | plan cum tokens |'
      ' cum Δ | pass |',
    )
    ..writeln('|---|---|---|---|---|---|---|');
  var baseTok = 0;
  var planTok = 0;
  var baseCalls = 0;
  var planCalls = 0;
  var allPass = true;
  for (final (br, pr) in rows) {
    if (br != null) {
      baseTok += br.cumulativeTokens;
      baseCalls += br.llmCalls;
      allPass &= br.passed;
    }
    if (pr != null) {
      planTok += pr.cumulativeTokens;
      planCalls += pr.llmCalls;
      allPass &= pr.passed;
    }
    final id = (br ?? pr)!.taskId;
    final delta = br == null || pr == null || br.cumulativeTokens == 0
        ? null
        : ((pr.cumulativeTokens - br.cumulativeTokens) /
              br.cumulativeTokens *
              100);
    b.writeln(
      '| $id '
      '| ${br?.llmCalls ?? '—'} | ${pr?.llmCalls ?? '—'} '
      '| ${br?.cumulativeTokens ?? '—'} | ${pr?.cumulativeTokens ?? '—'} '
      '| ${delta == null ? '—' : '${delta.toStringAsFixed(0)}%'} '
      '| ${(br?.passed ?? true) && (pr?.passed ?? true) ? '✅' : '❌'} |',
    );
    for (final r in [br, pr]) {
      if (r == null || tracePath == null) continue;
      File(tracePath).writeAsStringSync(
        '${jsonEncode({
              'task_id': r.taskId,
              'arm': identical(r, br) ? 'baseline' : 'plan',
              'backend': backendLabel,
              'model': modelLabel,
              'role_tags': ContextFragmentProtocol.roleTagsEnabled,
              'passed': r.passed,
              'llm_calls': r.llmCalls,
              'tokens_used_last_cut': r.tokensUsed,
              'cumulative_tokens': r.cumulativeTokens,
              'wall_ms': r.wallMs,
              if (r.toolErrors.isNotEmpty) 'tool_errors': r.toolErrors,
            })}\n',
        mode: FileMode.append,
      );
    }
  }
  b
    ..writeln()
    ..writeln(
      '**Totals (CUMULATIVE tokens)** — calls: $baseCalls → $planCalls'
      '${arms == 'both' ? ' (${((planCalls - baseCalls) / (baseCalls == 0 ? 1 : baseCalls) * 100).toStringAsFixed(0)}%)' : ''}, '
      'tokens: $baseTok → $planTok'
      '${arms == 'both' && baseTok > 0 ? ' (${((planTok - baseTok) / baseTok * 100).toStringAsFixed(0)}%)' : ''}',
    )
    ..writeln()
    ..writeln(
      allPass
          ? 'All runs passed — comparison fully valid.'
          : '⚠️ some tasks failed — treat deltas as indicative only.',
    );
  return b.toString();
}

/// Runs monolithic vs decomposed-real arms per task with any injected
/// backend, appends JSONL trace rows to [tracePath] when given, and returns
/// the markdown comparison table.
Future<String> runDecompositionProbe(
  List<CodingTask> tasks, {
  required GenerationHandler Function(CodingTask task) buildInnerHandler,
  String? tracePath,
  String backendLabel = 'scripted',
  String modelLabel = 'scripted',
  int maxTicks = 2000000,
}) async {
  stdout.writeln(
    'ADR 0009 real-model DECOMPOSITION probe ($backendLabel:$modelLabel) — '
    '${tasks.length} tasks\n',
  );

  final b = StringBuffer()
    ..writeln(
      '| task | mono calls | decomp calls | mono cum | decomp cum |'
      ' cum Δ | steps✓ | mono pass | decomp pass | fail-mode |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|---|---|');
  var mcalls = 0;
  var dcalls = 0;
  var mtok = 0;
  var dtok = 0;
  for (final task in tasks) {
    stdout.writeln('▶ ${task.id}');
    final mono = await runPlanArm(
      task,
      planFrontier: false,
      buildHandler: buildInnerHandler,
      maxTicks: maxTicks,
    );
    stdout.writeln(
      '  monolithic: ${mono.passed ? "PASS" : "FAIL"} — '
      '${mono.llmCalls} calls, cum ${mono.cumulativeTokens} tokens',
    );

    final dec = await runDecomposedArmReal(
      task,
      buildInnerHandler: buildInnerHandler,
    );
    stdout.writeln(
      '  decomposed: ${dec.passed ? "PASS" : "FAIL"} — '
      '${dec.llmCalls} call(s), cum ${dec.cumulativeTokens} tokens, '
      'steps verified=${dec.stepsVerified}'
      '${dec.failureMode.isEmpty ? "" : " [${dec.failureMode}]"}',
    );

    mcalls += mono.llmCalls;
    dcalls += dec.llmCalls;
    mtok += mono.cumulativeTokens;
    dtok += dec.cumulativeTokens;
    final delta = mono.cumulativeTokens == 0
        ? 0.0
        : (dec.cumulativeTokens - mono.cumulativeTokens) /
              mono.cumulativeTokens *
              100;
    b.writeln(
      '| ${task.id} | ${mono.llmCalls} | ${dec.llmCalls} '
      '| ${mono.cumulativeTokens} | ${dec.cumulativeTokens} '
      '| ${delta.toStringAsFixed(0)}% | ${dec.stepsVerified} '
      '| ${mono.passed ? '✅' : '❌'} | ${dec.passed ? '✅' : '❌'} '
      '| ${dec.failureMode.isEmpty ? '—' : dec.failureMode} |',
    );
    if (tracePath != null) {
      File(tracePath).writeAsStringSync(
        '${jsonEncode({
              'task_id': task.id,
              'arm': 'monolithic',
              'backend': backendLabel,
              'model': modelLabel,
              'passed': mono.passed,
              'llm_calls': mono.llmCalls,
              'cumulative_tokens': mono.cumulativeTokens,
            })}\n',
        mode: FileMode.append,
      );
      File(tracePath).writeAsStringSync(
        '${jsonEncode({
              'task_id': task.id,
              'arm': 'decomposed-real',
              'backend': backendLabel,
              'model': modelLabel,
              'passed': dec.passed,
              'llm_calls': dec.llmCalls,
              'cumulative_tokens': dec.cumulativeTokens,
              'steps_verified': dec.stepsVerified,
              'failure_mode': dec.failureMode,
            })}\n',
        mode: FileMode.append,
      );
    }
  }

  b
    ..writeln()
    ..writeln(
      '**Totals** — calls: $mcalls → $dcalls '
      '(${((dcalls - mcalls) / (mcalls == 0 ? 1 : mcalls) * 100).toStringAsFixed(0)}%), '
      'cum tokens: $mtok → $dtok '
      '(${((dtok - mtok) / (mtok == 0 ? 1 : mtok) * 100).toStringAsFixed(0)}%)',
    )
    ..writeln()
    ..writeln(
      'decomposed arm = ONE guided decompose call + fully mechanical '
      'execution/verification.',
    );
  return b.toString();
}
