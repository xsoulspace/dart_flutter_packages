// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 decomposition mechanics — per-step acceptance criteria in-frame.
///
/// What's under test: the DECOMPOSED execution shape.
///   - steps are entities with per-step claims + mechanical acceptance
///     predicates (spawned upfront — the decompose-once agentic act is
///     MOCKED here; its fidelity is a separate measurement);
///   - each decision sees ONLY the current step's claim + criterion
///     (acceptance-in-frame → tighter cuts than whole-goal prompts);
///   - after each tool result the executed step is verified MECHANICALLY
///     (matched by tool name + path from the result beat);
///   - the frontier opens a continuation naming the NEXT step only while
///     open steps remain — zero close-out calls at the end.
///
/// Comparison vs the monolithic baseline (same writes, default ReAct):
/// calls and cumulative tokens.
///
/// Run: `dart run benchmark/decomposition_experiment.dart [filter]`
library;

import 'dart:io';

import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_core/src/agent/systems/decision_flow_system.dart';

import 'coding_suite/checkers.dart';
import 'coding_suite/scripted_handler.dart';
import 'coding_suite/task_spec.dart';
import 'plan_frontier_arms.dart' show CumulativeTokenMeter;

// ---- Experiment-local components -------------------------------------------

class StepClaim implements Component {
  StepClaim(this.text);
  final String text;
}

class StepAction implements Component {
  StepAction(this.toolName, this.arguments);
  final String toolName;
  final Map<String, dynamic> arguments;
}

class StepIndex implements Component {
  StepIndex(this.value);
  final int value;
}

// Reuse arms-file components where possible via local copies to keep this
// self-contained:
class DStepStatus implements Component {
  DStepStatus(this.value);
  final String value; // open | verified
}

class DGoalRef implements Component {
  const DGoalRef(this.goal);
  final Entity goal;
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
        in world.query2<DGoalRef, DStepStatus>().toList()) {
      // Query tuples lead with a WorldEntity facade: .get works directly.
      if (status.value == 'open') {
        currentAction = (entity as dynamic).get<StepAction>() as StepAction?;
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
      structuredOutput: {'text': 'executing step'},
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

/// After each tool result: verify the EXECUTED step mechanically (match by
/// tool name + path), flip its status, and open the NEXT step's decision —
/// or terminate when all steps are verified. Pure graph logic.
Future<void> stepFrontierSystem(World world) async {
  for (final _ in world
      .query2<Actor, ToolResultPendingMarker>()
      .toList()) {
    // Locate the first open step and verify ITS predicate against the jail.
    for (final (stepEntity, _, status)
        in world.query2<DGoalRef, DStepStatus>().toList()) {
      if (status.value != 'open') continue;
      final claim = stepEntity.get<StepClaim>()!;
      final action = stepEntity.get<StepAction>()!;
      final index = stepEntity.get<StepIndex>()!.value;
      final root = world.getResource<FsToolsRootResource>().root;

      var passed = false;
      var detail = '';
      try {
        if (action.toolName == 'write') {
          final target = root.resolve(action.arguments['path'] as String);
          passed =
              File(target).existsSync() && File(target).readAsStringSync() ==
                  action.arguments['content'] as String;
          detail = passed ? '' : 'file ${action.arguments['path']} content mismatch';
        } else {
          passed = true; // non-write steps trusted in v1
        }
      } catch (e) {
        detail = e.toString();
      }

      stepEntity.insert(DStepStatus(passed ? 'verified' : 'open'));
      if (passed) {
        stdout.writeln('[step $index] ✅ ${claim.text}');
      } else {
        stdout.writeln('[step $index] ⚠️ retry: $detail');
      }

      // Frontier advance: open the NEXT step's decision on the ACTOR (the
      // decisionFlow/grant machinery only reads actors). When no open step
      // remains, open NOTHING — the episode terminates without a close-out
      // call. NOTE: this replaces ReAct continuation entirely (registered
      // below with an empty flow).
      if (!passed) {
        break; // failed step stays open; re-decide it with criterion in-frame
      }
      String? next;
      for (final (e2, _, s2) in world.query2<DGoalRef, DStepStatus>().toList()) {
        final i2 = e2.get<StepIndex>()!.value;
        if (s2.value == 'open' && i2 > index) {
          next = e2.get<StepClaim>()!.text;
          break;
        }
      }
      if (next != null &&
          world.getResource<StepFrontierConfig>().openNextDecisions) {
        for (final (actorEntity, _, _) in world.query2<Actor, DGoalRef>().toList()) {
          if (!actorEntity.has<OpenDecision>()) {
            try {
              actorEntity.insert(
                OpenDecision(
                  prompt: 'Next step: $next\n'
                      'Acceptance: the written file must exist with exactly the '
                      'required content. Perform exactly this step.',
                ),
              );
              // ignore: avoid_print
            } catch (e) {
              // ignore: avoid_print
              stdout.writeln('[dbg] actor insert THREW: ' + e.toString());
            }
          }
          break;
        }
      }
      break; // handle ONE step per tick
    }
  }
  world.flush();
}

// ---- Harness-side resource for the jail root -------------------------------

class FsToolsRootResource extends Resource {
  FsToolsRootResource(this.root);
  final FsToolsRoot root;
}

// ---- Experiment ------------------------------------------------------------

/// Decompose a task into steps derived from its canned behavior (the
/// decompose-once transform, mocked): one write-step per scripted action,
/// each with an exact-content acceptance predicate.
List<(StepClaim, StepAction)> decompose(CodingTask task) {
  final steps = <(StepClaim, StepAction)>[];
  for (final s in scriptedBehaviors[task.id]!) {
    steps.add((
      StepClaim('write ${s.arguments['path']}'),
      StepAction(s.toolName, s.arguments),
    ));
  }
  return steps;
}

Future<void> main(List<String> args) async {
  final filter = args.isEmpty ? 'refactor_01' : args.first;
  final tasks = loadTasks('benchmark/coding_suite/tasks')
      .where((t) => t.id.contains(filter))
      .toList();

  final b = StringBuffer()
    ..writeln('| task | base calls | decomp calls | base cum | decomp cum |'
        ' cum Δ | pass |')
    ..writeln('|---|---|---|---|---|---|---|');
  var allPass = true;

  for (final task in tasks) {
    // --- Baseline: monolithic (default ReAct, same writes).
    final baseWorld = await _buildWorld(task, monolithic: true);
    final baseStart = _responses(baseWorld.$1);
    Stopwatch sw = Stopwatch()..start();
    await HarnessLoop(world: baseWorld.$1).runUntilIdle(maxTicks: 2000000);
    final baseCalls = _responses(baseWorld.$1) - baseStart;
    final baseTok = baseWorld.$2[0];
    final basePassed = _check(task, baseWorld.$3);
    sw.stop();

    // --- Decomposed: per-step decisions + mechanical per-step verify.
    final dWorld = await _buildWorld(task, monolithic: false);
    final dStart = _responses(dWorld.$1);
    await HarnessLoop(world: dWorld.$1).runUntilIdle(maxTicks: 2000000);
    final dCalls = _responses(dWorld.$1) - dStart;
    final dTok = dWorld.$2[0];
    final dPassed = _check(task, dWorld.$3);

    allPass &= basePassed && dPassed;
    final delta = baseTok == 0 ? 0 : ((dTok - baseTok) / baseTok * 100);
    b.writeln(
      '| ${task.id} | $baseCalls | $dCalls '
      '| $baseTok | $dTok | ${delta.toStringAsFixed(0)}% '
      '| ${(basePassed && dPassed) ? '✅' : '❌'} |',
    );
  }

  b..writeln()
    ..writeln(allPass
        ? '✅ both shapes pass all checkers.'
        : '⚠️ failures present.');
  stdout.writeln(b);
  exit(0);
}

int _responses(World world) => world.events.hasRegistered<ActorGenerateResponse>()
    ? world.events.stats<ActorGenerateResponse>().sent
    : 0;

bool _check(CodingTask task, Directory jail) {
  for (final c in task.checkers) {
    if (!evaluateChecker(c, jail.path).passed) return false;
  }
  return task.checkers.isNotEmpty;
}

Future<(World, List<int>, Directory)> _buildWorld(
  CodingTask task, {
  required bool monolithic,
}) async {
  final jail = await Directory.systemTemp.createTemp('decomp_${task.id}_');
  for (final f in task.fixtures) {
    final file = File('${jail.path}/${f.path}');
    await file.parent.create(recursive: true);
    await file.writeAsString(f.content);
  }

  final world = World()..addPlugin(AgentPlugin());
  world.components
    ..registerObjectComponent<StepClaim>()
    ..registerObjectComponent<StepAction>()
    ..registerObjectComponent<StepIndex>()
    ..registerObjectComponent<DStepStatus>()
    ..registerObjectComponent<DGoalRef>();
  final router = ModelRouter(inferenceClientsBuilders: {});
  final modelId = ModelId('suite-model');
  router.models[modelId] =
      Model(id: modelId, name: DefaultModelNames.appleFoundation);
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(AgencyPolicy(maxConcurrent: 1))
    ..upsertResource(StepFrontierConfig())
    ..flush();

  final tokenTotal = <int>[0];
  final inner = monolithic
      ? ScriptedSuiteHandler(taskId: task.id) as GenerationHandler
      : StepExecutorHandler();
  world.getResource<GenerationHandlerResource>().registerDefault(
        CumulativeTokenMeter(inner, tokenTotal),
      );

  final root = FsToolsRoot(jail.path);
  world.upsertResource(FsToolsRootResource(root));
  final registry = ToolRegistry();
  fsTools(root).forEach(registry.register);

  if (monolithic) {
    // Decompose-once MOCKED note applies to both arms equally: the baseline
    // gets the same writes as one canned script (stateless re-emit handler —
    // bounded by maxToolRounds, matching Phase 4 behavior).
  } else {
    // NO ReAct continuation: the ONLY continuation decisions are opened by
    // stepFrontierSystem (frontier advance). Terminates without close-out.
    world.upsertResource(DecisionFlowResource(DecisionFlow(const [])));
    // Per-step verification is mechanical graph logic (stepFrontierSystem).
    world.schedule(Schedules.narrative).add(stepFrontierSystem,
        name: 'stepFrontier');
  }
  world.getResource<ToolRegistryResource>().register('default', registry);

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

  if (!monolithic) {
    // Decompose-once (mocked): goal + steps with per-step criteria.
    final goal = world.spawnComponents([Goal(text: task.prompt)]);
    world.upsertComponent(actor, DGoalRef(goal));
    final steps = decompose(task);
    for (var i = 0; i < steps.length; i++) {
      world.spawnComponents([
        DGoalRef(goal),
        DStepStatus('open'),
        steps[i].$1,
        steps[i].$2,
        StepIndex(i),
      ]);
    }
  }
  world.flush();
  return (world, tokenTotal, jail);
}

// =============================================================================
// Real-model decomposed arm: decompose-once via guided schema, then MECHANICAL
// execution of the planned steps (predictable parts never touch the LLM).
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
/// [mechanicalStepExecutorSystem].
class DecomposeDraftResource extends Resource {
  DecomposeDraftResource();
  List<Map<String, dynamic>> steps = const [];
  bool get hasDraft => steps.isNotEmpty;
}

String decomposeInstruction(CodingTask task) => 'GOAL: ${task.prompt}\n\n'
    'Decompose this goal into an ordered list of file-write steps. For each '
    'step provide the workspace-relative "path" and the FULL final file '
    '"content". The harness will write and verify each step mechanically — '
    'plan completely and precisely.';

/// Executes the first open step's write MECHANICALLY (through the jailed
/// `write` tool executor — seam 3), then lets [stepFrontierSystem] verify it.
/// Runs every tick; no-ops when no draft/steps are pending.
Future<void> mechanicalStepExecutorSystem(World world) async {
  // Execute the first open step through the jailed write executor.
  // (Draft transformation is [decomposeTransformSystem]'s job, which runs
  // earlier on the same schedule.)
  StepAction? action;
  WorldEntity? stepFacade;
  for (final (e, _, st) in world.query2<DGoalRef, DStepStatus>().toList()) {
    if (st.value == 'open') {
      action = e.get<StepAction>();
      stepFacade = e;
      break;
    }
  }
  if (action == null || stepFacade == null) return;
  final toolDef = world
      .getResource<ToolRegistryResource>()
      .get('default')
      ?.get(const ToolName('write'));
  if (toolDef == null) return;
  await toolDef.execute(action.arguments);
}

/// Handler wrapper: captures a structured `steps` payload from the decompose
/// response into [DecomposeDraftResource], then passes through unchanged.
class DecomposeCaptureHandler implements GenerationHandler {
  DecomposeCaptureHandler(this.inner, this.draft, this.total);
  final GenerationHandler inner;
  final DecomposeDraftResource draft;
  final List<int> total;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final situation = world.getEntity(request.actorEntity).$1.get<Situation>();
    if (situation != null) total[0] += situation.tokensUsed;

    // First call (draft pending, no steps yet): this IS the decompose call.
    // Strip the tool registry so a wrapping StructuredToolDecisionHandler
    // passes through to the backend with the REQUEST's decompose schema
    // instead of forcing its act-vs-answer schema.
    final isDecomposeCall =
        !draft.hasDraft && _stepsSpawned(world) == 0;
    final effective = isDecomposeCall ? _stripRegistry(request) : request;
    final response = await inner.generate(world, effective);
    if (isDecomposeCall) {
      // ignore: avoid_print
      final rawFlat =
          (response.rawOutput ?? '<null>').replaceAll('\n', ' ');
      stdout.writeln('[dbg] decompose raw='
          + rawFlat.substring(0, rawFlat.length > 600 ? 600 : rawFlat.length));
      // ignore: avoid_print
      stdout.writeln('[dbg] decompose structured keys='
          + response.structuredOutput.keys.toString());
    }
    return response;
  }

  static int _stepsSpawned(World world) =>
      world.query2<DGoalRef, DStepStatus>().length;

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
}

/// Frontier behavior: whether verifying a step opens an LLM decision for the
/// NEXT step. True for the scripted decomposition arm (model executes each
/// step); false for the real-model arm (steps execute MECHANICALLY from the
/// decompose plan — no further agency at all).
class StepFrontierConfig extends Resource {
  StepFrontierConfig({this.openNextDecisions = true});
  final bool openNextDecisions;
}

/// Result of one real-model decomposed run.
class DecompRunResult {
  DecompRunResult({
    required this.passed,
    required this.llmCalls,
    required this.cumulativeTokens,
    required this.stepsVerified,
    this.failureMode = '',
  });
  final bool passed;
  final int llmCalls;
  final int cumulativeTokens;
  final int stepsVerified;
  final String failureMode;
}

/// Real-model decomposed arm: ONE guided decompose call → mechanical
/// execution of every planned step through the jailed write executor →
/// per-step verification → termination without further LLM calls.
Future<DecompRunResult> runDecomposedArmReal(
  CodingTask task, {
  required GenerationHandler Function(CodingTask task) buildInnerHandler,
  int maxTicks = 2000000,
}) async {
  final jail = await Directory.systemTemp.createTemp('decomp_real_${task.id}_');
  try {
    for (final f in task.fixtures) {
      final file = File('${jail.path}/${f.path}');
      await file.parent.create(recursive: true);
      await file.writeAsString(f.content);
    }

    final world = World()..addPlugin(AgentPlugin());
    world.components
      ..registerObjectComponent<StepClaim>()
      ..registerObjectComponent<StepAction>()
      ..registerObjectComponent<StepIndex>()
      ..registerObjectComponent<DStepStatus>()
      ..registerObjectComponent<DGoalRef>();
    final router = ModelRouter(inferenceClientsBuilders: {});
    final modelId = ModelId('suite-model');
    router.models[modelId] =
        Model(id: modelId, name: DefaultModelNames.appleFoundation);
    final draft = DecomposeDraftResource();
    final tokenTotal = <int>[0];
    world
      ..upsertResource(ModelRouterResource(router))
      ..upsertResource(ToolRegistryResource())
      ..upsertResource(AgencyPolicy(maxConcurrent: 1))
      ..upsertResource(draft)
      ..flush();

    // NO ReAct continuation: the only LLM call is the decompose call.
    world.upsertResource(DecisionFlowResource(DecisionFlow(const [])));
    world.upsertResource(StepFrontierConfig(openNextDecisions: false));

    final inner = buildInnerHandler(task);
    var llmCalls = 0;
    world.getResource<GenerationHandlerResource>().registerDefault(
          _CountingHandler(
            DecomposeCaptureHandler(inner, draft, tokenTotal),
            () => llmCalls++,
          ),
        );

    final root = FsToolsRoot(jail.path);
    world.upsertResource(FsToolsRootResource(root));
    final registry = ToolRegistry();
    fsTools(root).forEach(registry.register);
    world.getResource<ToolRegistryResource>().register('default', registry);

    // Mechanical pipeline on Narrative: transform → execute → verify/advance.
    world.schedule(Schedules.narrative)
      ..add(decomposeTransformSystem, name: 'decomposeTransform')
      ..then(mechanicalStepExecutorSystem, name: 'mechanicalExecute')
      ..then(stepFrontierSystem, name: 'stepFrontier');

    final scene = world.spawnComponents([const Scene(), SceneFrame()]);
    final actor = world.spawnComponents([
      Actor(agentId: AgentId.create()),
      ActorModel(modelId: modelId),
      ActorSystemPrompt(text: task.systemPrompt),
      ActorThreads(threads: []),
      const ActorTools(registryName: 'default'),
      PresentInScene(sceneEntity: scene),
      OpenDecision(
        prompt: decomposeInstruction(task),
        schema: decomposeStepsSchema,
      ),
    ]);
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    final goal = world.spawnComponents([Goal(text: task.prompt)]);
    world.upsertComponent(actor, DGoalRef(goal));
    world.flush();

    await HarnessLoop(world: world).runUntilIdle(maxTicks: maxTicks);

    var stepsVerified = 0;
    for (final (_, _, st) in world.query2<DGoalRef, DStepStatus>().toList()) {
      if (st.value == 'verified') stepsVerified++;
    }
    final checkersPassed = task.checkers.isNotEmpty &&
        task.checkers.every((c) => evaluateChecker(c, jail.path).passed);
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
      cumulativeTokens: tokenTotal[0],
      stepsVerified: stepsVerified,
      failureMode: failureMode,
    );
  } finally {
    jail.delete(recursive: true);
  }
}

/// Consumes [DecomposeDraftResource]: spawns step entities from the captured
/// draft. Pure graph logic.
Future<void> decomposeTransformSystem(World world) async {
  final draftResource = world.getResource<DecomposeDraftResource>();
  if (!draftResource.hasDraft) return;
  Entity? goal;
  for (final (g, _, _) in world.query2<Goal, DGoalRef>().toList()) {
    goal = g.entity;
    break;
  }
  if (goal == null) return;
  for (var i = 0; i < draftResource.steps.length; i++) {
    final st = draftResource.steps[i];
    world.spawnComponents([
      DGoalRef(goal),
      DStepStatus('open'),
      StepClaim('write ${st['path']}'),
      StepAction('write', {'path': st['path'], 'content': st['content']}),
      StepIndex(i),
    ]);
  }
  draftResource.steps = const [];
}

/// Counts generate() invocations (one per decision dispatched).
class _CountingHandler implements GenerationHandler {
  _CountingHandler(this.inner, this.onCall);
  final GenerationHandler inner;
  final void Function() onCall;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) {
    onCall();
    return inner.generate(world, request);
  }
}
