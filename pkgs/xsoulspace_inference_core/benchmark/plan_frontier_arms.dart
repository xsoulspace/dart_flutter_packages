// ignore_for_file: lines_longer_than_80_chars

/// Shared A/B arms for the ADR 0009 plan-frontier falsification work.
///
/// Both arms construct the identical world (fixtures, handler, Goal+step
/// entities); the ONLY variable is the decision flow:
/// - baseline (`planFrontier: false`) → default ReAct continuation after
///   every tool result; the model pays one extra call to say "done".
/// - plan frontier (`planFrontier: true`) → goal success criteria registered
///   as a seam-3 verifier tool, executed mechanically by
///   [goalVerificationSystem]; [PlanFrontierPolicy] abstains once verified,
///   so the loop terminates without a close-out call.
///
/// See docs/agent/results_plan_falsification.md.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'coding_suite/checkers.dart';
import 'coding_suite/task_spec.dart';

/// Experiment-local verification outcome stamped by the mechanical
/// goalVerificationSystem. The frontier policy reads ONLY this component —
/// it never touches the filesystem, keeping the policy pure.
class GoalVerified implements Component {
  GoalVerified({required this.passed, this.detail = ''});
  final bool passed;
  final String detail;
}

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

/// Experiment-local backlink: which goal entity this ACTOR serves.
class ActorGoalRef implements Component {
  const ActorGoalRef(this.goal);
  final Entity goal;
}

/// How many idle nudges this actor has received (bounds the verify→nudge
/// loop: total model calls ≤ initial attempt + maxIdleNudges).
class IdleNudgeCount implements Component {
  IdleNudgeCount(this.value);
  int value;
}

/// Max idle nudges before giving up on an unverified goal (bounded loop).
/// AFM probe data (runs/plan_probe_afm_idlerule.jsonl): with 2 nudges,
/// hopeless tasks re-opened full tool-round chains (+16 calls on edit_04)
/// with zero pass-rate gain. One nudge catches the answer-without-acting
/// flake class (see idle_verify_proof.dart) at bounded cost.
const int maxIdleNudges = 1;

/// The plan-frontier policy: fires exactly where [ReActContinuationPolicy]
/// fires (fresh tool result), but consults the GOAL first — via the pure
/// [GoalVerified] component, never via I/O.
///
/// - All success criteria hold (verification landed mechanically) → abstain
///   (no agency; the loop goes idle).
/// - Any criterion fails → open ONE tight continuation carrying the failing
///   predicate details (mechanical feedback, not narrative).
///
/// Purity note: an earlier draft evaluated checkers inside this policy by
/// reading the jail directly — a documented deviation, now closed. Predicate
/// execution lives in [goalVerificationSystem], which runs the registered
/// `verify_workspace` tool through the same executor path tools take; the
/// policy consumes only its component/beat residue.
class PlanFrontierPolicy implements DecisionPolicy {
  PlanFrontierPolicy();

  @override
  String get name => 'plan_frontier';

  @override
  DecisionDraft? evaluate(DecisionContext ctx) {
    if (!ctx.has<ToolResultPendingMarker>()) return null;
    final verified = ctx.get<GoalVerified>();

    if (verified == null) return null; // verification has not landed yet
    _updateStepEntities(ctx.world, verified.passed);
    if (verified.passed) {
      // Goal vector satisfied — mechanically done. No LLM call is spent on
      // asking the model whether it finished. This is the entire bet.
      return null;
    }
    return DecisionDraft(
      prompt: 'Goal not yet verified. Failing criteria:\n${verified.detail}\n'
          'Continue working toward the goal.',
    );
  }

  void _updateStepEntities(World world, bool allPassed) =>
      _updateStepStatuses(world, allPassed);
}

/// Flip every step entity's status (shared by policy + idle verifier).
void _updateStepStatuses(World world, bool allPassed) {
  for (final (entity, _, _) in world.query2<StepGoalLink, StepStatus>()
      .toList()) {
    entity.insert(StepStatus(allPassed ? 'verified' : 'failed'));
  }
}

/// Mechanical verification: runs after tool results land, executes the
/// `verify_workspace` tool through [ToolExecutorResource] (the same path
/// LLM-dispatched tool calls take — predicates are seam-3 tools), and stamps
/// [GoalVerified] + a verifier observation beat onto the graph. Never calls
/// a model.
Future<void> goalVerificationSystem(World world) async {
  for (final (entity, _, _) in world
      .query2<Actor, ToolResultPendingMarker>()
      .toList()) {
    // Prefer the graph-ready executor resource; fall back to the registry's
    // inline definition (same precedence toolExecutionSystem uses).
    final executor = world
        .getResource<ToolExecutorResource>()
        .get(const ToolName('verify_workspace'));
    final toolDef = world
        .getResource<ToolRegistryResource>()
        .get('default')
        ?.get(const ToolName('verify_workspace'));
    if (executor == null && toolDef == null) continue;
    Object? output;
    try {
      output = executor != null
          ? await executor(const {})
          : await toolDef!.execute(const {});
    } catch (_) {
      rethrow;
    }
    // ToolDef outputs may arrive JSON-encoded; normalize before reading.
    Object? decoded = output;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {}
    }
    final map = decoded is Map ? decoded : null;
    final passed = map?['passed'] == true;
    final detail = map == null ? '$output' : '${map['failures'] ?? ''}';
    entity.insert(GoalVerified(passed: passed, detail: detail));
    // Verifier provenance stays in the graph as an observation beat.
    final threads = entity.get<ActorThreads>()?.threads;
    if (threads == null || threads.isEmpty) continue;
    final beat = world.spawnComponents([
      TextContent('verify_workspace → ${passed ? 'pass' : 'fail'} $detail'),
      BeatStatus(BeatStatusEnum.complete),
      BeatModality(BeatModalityEnum.observation),
      BelongsToThread(threads.first),
    ]);
    indexBeat(
      world,
      beat,
      keywordsOf('verify_workspace ${passed ? 'pass' : 'fail'}'),
    );
  }
  // ---- Idle-goal verification -------------------------------------------
  // Coverage rule (ADR 0009 §3): the frontier only gates after TOOL results,
  // so an episode where the model ANSWERS WITHOUT ACTING would otherwise end
  // silently on an unverified goal. While an actor sits idle with an open
  // goal: verify mechanically; on failure, nudge ONCE per strike, bounded by
  // [maxIdleNudges]. Purely mechanical — never a model call.
  for (final (entity, _, _) in world.query2<Actor, ActorGoalRef>().toList()) {
    // pendingWork MUST mirror HarnessLoop.canSleep() — including IN-FLIGHT
    // tool tasks and unconsumed result events, not just actor components.
    // Otherwise the idle verifier races an executing write and nudges based
    // on stale workspace state (observed: strikes firing before the tool
    // result landed).
    final pendingWork = entity.has<OpenDecision>() ||
        entity.has<Agency>() ||
        entity.has<AwaitingResponse>() ||
        entity.has<ToolResultPendingMarker>() ||
        !world.getResource<TaskRegistryResource>().isEmpty ||
        (world.events.hasRegistered<ToolResultEvent>() &&
            world.events.reader<ToolResultEvent>().isNotEmpty);
    if (pendingWork) continue;
    final verified = entity.get<GoalVerified>();
    if (verified != null && verified.passed) continue; // goal achieved
    final strikes = entity.get<IdleNudgeCount>()?.value ?? 0;

    // Verify NOW (same seam-3 verifier, same precedence as above).
    final vExecutor = world
        .getResource<ToolExecutorResource>()
        .get(const ToolName('verify_workspace'));
    final vDef = world
        .getResource<ToolRegistryResource>()
        .get('default')
        ?.get(const ToolName('verify_workspace'));
    if (vExecutor == null && vDef == null) continue;
    Object? vOut;
    try {
      vOut = vExecutor != null
          ? await vExecutor(const {})
          : await vDef!.execute(const {});
    } catch (_) {
      continue; // verifier failure is data for the next tick, not fatal here
    }
    Object? vDecoded = vOut;
    if (vDecoded is String) {
      try {
        vDecoded = jsonDecode(vDecoded);
      } catch (_) {}
    }
    final vMap = vDecoded is Map ? vDecoded : null;
    final vPassed = vMap?['passed'] == true;
    final vDetail = vMap == null ? '$vOut' : '${vMap['failures'] ?? ''}';
    _updateStepStatuses(world, vPassed);
    entity.insert(GoalVerified(passed: vPassed, detail: vDetail));
    if (!vPassed && strikes < maxIdleNudges) {
      entity.insert(IdleNudgeCount(strikes + 1));
      // Open the nudge decision DIRECTLY here — do NOT defer via a marker
      // component. Deferred markers are invisible to canSleep(), so
      // runUntilIdle would exit before the policy could turn them into a
      // decision (the exact "idle ⇒ nothing stranded" violation from the
      // 2026-08 postmortem). Inserting the decision in-system keeps the new
      // work visible to the loop within this tick.
      entity.insert(
        OpenDecision(
          prompt: 'Goal not yet verified. Failing criteria:\n$vDetail\n'
              'Continue working toward the goal.',
        ),
      );
    }
  }

  // Flush NOW: the frontier policy reads [GoalVerified] at the START of the
  // next tick's AgencyGrant schedule. ecsly component inserts are queued
  // commands; without this flush the policy sees stale state and abstains,
  // silently ending multi-action tasks after one action. (Registered on the
  // Narrative schedule, which always runs after Mechanical's flush — but
  // this system stays correct wherever hosts place it.)
  world.flush();
}


/// Cumulative token accounting: [Situation.tokensUsed] is per-decision
/// (overwritten by every projection), so summing actors' final situations —
/// as the Phase 4 runner did — measures "last cut size", not spend. This
/// meter observes the situation exactly once per decision (at handler entry,
/// i.e. post-projection, pre-dispatch) and accumulates honestly.
///
/// No core change: projection semantics untouched; benchmark-side
/// bookkeeping only.
class CumulativeTokenMeter implements GenerationHandler {
  CumulativeTokenMeter(this.inner, this.total);
  final GenerationHandler inner;

  /// Single-element box mutated by [generate].
  final List<int> total;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) {
    final situation = world.getEntity(request.actorEntity).$1.get<Situation>();
    if (situation != null) total[0] += situation.tokensUsed;
    return inner.generate(world, request);
  }
}

class PlanRow {
  PlanRow({
    required this.taskId,
    required this.passed,
    required this.llmCalls,
    required this.tokensUsed,
    required this.wallMs,
    required this.mechanicalVerifications,
    required this.stepStatuses,
    this.cumulativeTokens = 0,
    this.toolErrors = const [],
  });
  final String taskId;
  final bool passed;
  final int llmCalls;

  /// Last-decision projection size (legacy field, kept for comparability).
  final int tokensUsed;

  /// Honest spend: sum of every decision's projection size (see
  /// [CumulativeTokenMeter]).
  final int cumulativeTokens;

  /// Distinct FULL tool-error outputs observed during the run (the native
  /// logger truncates at ~20 chars — useless for classification). Deduped.
  final List<String> toolErrors;
  final int wallMs;
  final int mechanicalVerifications;
  final List<String> stepStatuses;
}


/// Runs one task through one arm. Mirrors CodingSuiteRunner.runTask's
/// production world construction; see library doc for the arm difference.
Future<PlanRow> runPlanArm(
  CodingTask task, {
  required bool planFrontier,
  required GenerationHandler Function(CodingTask task) buildHandler,
  int maxTicks = 2000,
}) async {
  final jail = await Directory.systemTemp.createTemp('plan_exp_${task.id}_');
  try {
    for (final f in task.fixtures) {
      final file = File('${jail.path}/${f.path}');
      await file.parent.create(recursive: true);
      await file.writeAsString(f.content);
    }

    final world = World()..addPlugin(AgentPlugin());
    // Experiment-local components (ADR 0009 §2 shape preview).
    world.components
      ..registerObjectComponent<StepGoalLink>()
      ..registerObjectComponent<StepStatus>()
      ..registerObjectComponent<GoalVerified>()
      ..registerObjectComponent<ActorGoalRef>()
      ..registerObjectComponent<IdleNudgeCount>();
    final router = ModelRouter(inferenceClientsBuilders: {});
    final modelId = ModelId('suite-model');
    router.models[modelId] =
        Model(id: modelId, name: DefaultModelNames.appleFoundation);
    world
      ..upsertResource(ModelRouterResource(router))
      ..upsertResource(ToolRegistryResource())
      ..upsertResource(AgencyPolicy(maxConcurrent: 1))
      ..flush();

    final tokenTotal = <int>[0];
    world.getResource<GenerationHandlerResource>().registerDefault(
          CumulativeTokenMeter(buildHandler(task), tokenTotal),
        );
    final registry = ToolRegistry();
    fsTools(FsToolsRoot(jail.path)).forEach(registry.register);
    if (planFrontier) {
      // Goal success criteria as a seam-3 verifier tool — the ONLY place the
      // jail filesystem is read. Executed mechanically by
      // [goalVerificationSystem], never by a model decision.
      registry.register(
        ToolDef.encode(
          name: const ToolName('verify_workspace'),
          description: 'Evaluate the goal success criteria against the '
              'workspace. Returns pass/fail per criterion.',
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
      // Mechanical verification inside the Mechanical schedule; the system
      // flushes itself so [GoalVerified] is visible to the next tick's
      // AgencyGrant pass (see note in goalVerificationSystem).
      // Registered on Narrative, which the loop always runs AFTER the whole
      // Mechanical schedule (incl. its flush): the pending-marker component
      // is guaranteed applied by the time this system queries it.
      world.schedule(Schedules.narrative).add(
            goalVerificationSystem,
            name: 'goalVerification',
          );
      // Replace the default ReAct flow with the plan frontier (ADR 0009 §3).
      world.upsertResource(
        DecisionFlowResource(DecisionFlow([PlanFrontierPolicy()])),
      );
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

    // Goal vector + step entity — durable facts in the graph (ADR 0009 §1–2).
    // Present in BOTH arms so entity bookkeeping never confounds the delta.
    final goal = world.spawnComponents([Goal(text: task.prompt)]);
    world.spawnComponents([StepGoalLink(goal), StepStatus('open')]);
    world.upsertComponent(actor, ActorGoalRef(goal));
    world.flush();

    final responsesAtStart = world.events.hasRegistered<ActorGenerateResponse>()
        ? world.events.stats<ActorGenerateResponse>().sent
        : 0;

    final sw = Stopwatch()..start();
    final loop = HarnessLoop(world: world);
    await loop.runUntilIdle(maxTicks: maxTicks);
    sw.stop();

    var verifications = 0;
    // Mechanical verifications: tool-result beats that landed while the
    // frontier machinery was active (each triggered a predicate evaluation
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

    // Capture FULL tool-error outputs for diagnosis (logger truncates).
    final toolErrors = <String>{};
    for (final (_, content, _) in world.query2<ToolResultContent, BeatStatus>()
        .toList()) {
      final out = content.output.toString();
      if (out.contains('"error"')) toolErrors.add(out);
    }

    final checkerResults = [
      for (final c in task.checkers) evaluateChecker(c, jail.path),
    ];
    final passed =
        checkerResults.isNotEmpty && checkerResults.every((c) => c.passed);

    return PlanRow(
      taskId: task.id,
      passed: passed,
      llmCalls: llmCalls,
      tokensUsed: tokensUsed,
      wallMs: sw.elapsedMilliseconds,
      mechanicalVerifications: planFrontier ? verifications : 0,
      cumulativeTokens: tokenTotal[0],
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
