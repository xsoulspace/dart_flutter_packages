// ignore_for_file: lines_longer_than_80_chars

/// Shared world construction for ADR 0009 experiments.
///
/// Every arm builds the identical jail, router, registry, actor, and scene;
/// the ONLY variable is the decision flow and handler. This module owns the
/// boilerplate so experiment files stay focused on their hypothesis.
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import '../benchmark/coding_suite/checkers.dart';
import '../benchmark/coding_suite/task_spec.dart';

// ---- Shared components -----------------------------------------------------

/// Verification outcome stamped by a mechanical verifier system.
class GoalVerified implements Component {
  GoalVerified({required this.passed, this.detail = ''});
  final bool passed;
  final String detail;
}

/// Step status component (ADR 0009 §2 data shape preview).
class StepStatus implements Component {
  StepStatus(this.value);
  final String value; // open | verified | failed
}

/// Backlink: which goal entity this step serves.
class StepGoalLink implements Component {
  const StepGoalLink(this.goal);
  final Entity goal;
}

/// Backlink: which goal entity this ACTOR serves.
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

/// Per-step claim text (decomposition experiments).
class StepClaim implements Component {
  StepClaim(this.text);
  final String text;
}

/// The mechanical action associated with a step (decomposition experiments).
class StepAction implements Component {
  StepAction(this.toolName, this.arguments);
  final String toolName;
  final Map<String, dynamic> arguments;
}

/// Ordering index for steps.
class StepIndex implements Component {
  StepIndex(this.value);
  final int value;
}

/// Max idle nudges before giving up on an unverified goal (bounded loop).
const int maxIdleNudges = 1;

// ---- Shared helpers ---------------------------------------------------------

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

/// Counts generate() invocations (one per decision dispatched).
class CountingHandler implements GenerationHandler {
  CountingHandler(this.inner, this.onCall);
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

/// Registers experiment-local components on [world].
void registerExperimentComponents(World world) {
  world.components
    ..registerObjectComponent<GoalVerified>()
    ..registerObjectComponent<StepGoalLink>()
    ..registerObjectComponent<StepStatus>()
    ..registerObjectComponent<ActorGoalRef>()
    ..registerObjectComponent<IdleNudgeCount>()
    ..registerObjectComponent<StepClaim>()
    ..registerObjectComponent<StepAction>()
    ..registerObjectComponent<StepIndex>();
}

/// Builds a bare experiment world with jail fixtures written, router,
/// agency policy, and token meter registered. Returns the jail directory so
/// callers can register tools / checkers against it.
Future<({World world, Directory jail, List<int> tokenTotal})>
buildExperimentWorld(
  CodingTask task, {
  required GenerationHandler buildHandler(),
}) async {
  final jail = await Directory.systemTemp.createTemp('exp_${task.id}_');
  for (final f in task.fixtures) {
    final file = File('${jail.path}/${f.path}');
    await file.parent.create(recursive: true);
    await file.writeAsString(f.content);
  }

  final world = World()..addPlugin(AgentPlugin());
  registerExperimentComponents(world);
  final router = ModelRouter(inferenceClientsBuilders: {});
  const modelId = ModelId('suite-model');
  router.models[modelId] = Model(
    id: modelId,
    name: DefaultModelNames.appleFoundation,
  );
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(AgencyPolicy(maxConcurrent: 1))
    ..flush();

  final tokenTotal = <int>[0];
  world.getResource<GenerationHandlerResource>().registerDefault(
    CumulativeTokenMeter(buildHandler(), tokenTotal),
  );
  return (world: world, jail: jail, tokenTotal: tokenTotal);
}

/// Spawns scene + actor with standard components; returns the actor entity.
Entity spawnStandardActor(
  World world, {
  required String systemPrompt,
  required String prompt,
  SchemaBundle? schema,
}) {
  const modelId = ModelId('suite-model');
  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: modelId),
    ActorSystemPrompt(text: systemPrompt),
    ActorThreads(threads: []),
    const ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: prompt, schema: schema ?? SchemaBundle.empty),
  ]);
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  return actor;
}

/// Registers fsTools rooted at [jail] under the default registry.
void registerFsTools(World world, Directory jail) {
  final registry = ToolRegistry();
  fsTools(FsToolsRoot(jail.path)).forEach(registry.register);
  world.getResource<ToolRegistryResource>().register('default', registry);
}

/// Evaluates all checkers against [jail]; true only when non-empty + all pass.
bool checkTask(CodingTask task, Directory jail) =>
    task.checkers.isNotEmpty &&
    task.checkers.every((c) => evaluateChecker(c, jail.path).passed);

/// Counts ActorGenerateResponse events sent since registration.
int responseCount(World world) =>
    world.events.hasRegistered<ActorGenerateResponse>()
    ? world.events.stats<ActorGenerateResponse>().sent
    : 0;

/// Result row for plan-frontier arms.
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
  final int tokensUsed;
  final int cumulativeTokens;
  final int wallMs;
  final int mechanicalVerifications;
  final List<String> toolErrors;
  final List<String> stepStatuses;
}

/// Result row for decomposition arms.
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
