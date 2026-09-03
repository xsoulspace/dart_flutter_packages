// ignore_for_file: lines_longer_than_80_chars

/// Closing-the-gap seams (gates B, C, Stage C, Stage D) as real, reusable,
/// deterministic, LLM-free-testable tooling built on the exported surface.
///
/// - Gate C: `askUserTool` — human-as-actor (a2h). A model-facing actor emits
///   a typed question/option menu; an injectable `HumanAnswerProvider`
///   replies; the actor resumes on the answer.
/// - Gate B: `defaultGoalFlow()` + `RunGradedGoalPolicy` — a Goal advances by
///   running code via the jailed `run` tool (Stage A) and stamps
///   [GoalVerified]; the run-graded continuation is the default flow, not an
///   experiment arm.
/// - Stage D: `planFromMatrix` — AE-style canonical matrix rows (wire shape)
///   → Goal + Step beats, so raw→structured→planning is a host seam
///   (ADR 0015/0017).
/// - Stage C (a2a): `spawnActorBranch` — an extra actor in the same world
///   with its own open decision, so a team can plan & build together.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show MeaningTreeExport;
import 'package:ecsly/ecsly.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, SchemaBundle, ToolDef, ToolName;

import '../../xsoulspace_agentic_harness.dart'
    show Actor, ActorModel, ActorSystemPrompt, AgentId, DecisionContext,
        DecisionDraft, DecisionFlow, DecisionPolicy, ModelId, OpenDecision,
        PresentInScene, ReActContinuationPolicy, Scene, SceneFrame;
import '../data_models/components.dart'
    show Actor, ActorGoalRef, ActorThreads, ActorTools, AttemptCount,
        EscalationRequest, Goal, GoalAttemptsExhausted, ToolRoundCount;
import '../meaning/intents.dart'
    show IntentCallState, IntentExpectation, IntentGoalSpec, callIntent;
import 'workspace_conventions.dart' show splitCheckCommand;
import '../meaning/meaning_tree.dart'
    show addMeaningNode, linkMeaning;
import '../narrative/components.dart'
    show ThreadStatus, ThreadStatusEnum;
import '../data_models/task.dart' show TaskHandle, TaskId;
import '../resources/resources.dart'
    show AgencyPolicy, TaskRegistryResource, ToolRegistryResource;
import '../schedules.dart' show Schedules;
import '../systems/decision_flow_system.dart'
    show ToolResultPendingMarker;
import 'world_builder.dart'
    show GoalVerified, StepAction, StepClaim, StepGoalLink, StepIndex,
        StepStatus;

// ---------------------------------------------------------------------------
// J7 — overseer ledger (the escalation budget the policy reads)
// ---------------------------------------------------------------------------

/// J7/J8 escalation ledger: how many overseer repair cycles the mover has
/// been granted, and whether a tier escalation already fired. The
/// [RunGradedGoalPolicy] reads `cycles` to widen its attempt allowance
/// MONOTONICALLY (base × (1 + cycles)) — never a reset; total attempts stay
/// bounded by base × (1 + maxCycles).
class OverseerLedger extends Resource {
  OverseerLedger({this.maxCycles = 1});

  /// How many overseer repair cycles may be granted (J7: 1; then J8.1).
  int maxCycles;

  /// Repair cycles granted so far.
  int cycles = 0;

  /// Whether a tier escalation (J8.1) already fired.
  bool escalatedToTier = false;

  /// A FINAL disposition was made (approve / escalate without budget) —
  /// no further overseer cycles may spawn.
  bool disposed = false;

  /// An overseer actor is spawned and its decision is pending.
  bool overseerPending = false;

  /// The structured gate failure the overseer is reviewing.
  String lastGateFailure = '';

  /// The brief the overseer saw (audit trail).
  String lastBrief = '';

  /// Every disposition decision (approve/repair/escalate) as data.
  final List<Map<String, Object?>> records = [];

  bool get canRepair => cycles < maxCycles;

  /// Whether the overseer may still act at all (spawn guard).
  bool get canAct => !disposed && (canRepair || !escalatedToTier);
}

// ---------------------------------------------------------------------------
// Gate C — human-as-actor (a2h): ask_user
// ---------------------------------------------------------------------------

/// The model-facing prompt raised to the human.
class AskUserPrompt {
  const AskUserPrompt({required this.text, this.options = const []});
  final String text;
  final List<String> options;
}

/// Injectable answer provider. CLI uses [stdinAskUser]; tests inject a queued
/// function. Returns null when the human declines / EOF.
typedef HumanAnswerProvider = Future<String?> Function(AskUserPrompt prompt);

/// The `ask_user` tool: the actor pauses, raises `question` + `options`, and
/// resumes with the human's typed answer as the tool result.
ToolDef askUserTool(HumanAnswerProvider provider) => ToolDef.encode(
  name: const ToolName('ask_user'),
  description:
      'Ask the user a question and get a typed answer. Optionally list an '
      'option menu. Pauses until the human replies; you resume with their '
      'answer as the tool result.',
  argsSchema: SchemaBundle(
    root: FM.object('ask_user', properties: () => [
      FM.prop('question', FM.string()),
      FM.prop('options', FM.array(FM.string())),
    ]),
  ),
  execute: (args) async {
    final map = args is Map ? args : const {};
    final q = map['question'];
    final opts = map['options'];
    final options = [
      if (opts is List)
        for (final o in opts)
          if (o is String) o,
    ];
    final answer =
        await provider(
            AskUserPrompt(text: q is String ? q : 'Please answer.', options: options),
          );
    return {'answered': true, 'answer': '$answer'};
  },
);

/// Default stdin-backed provider (CLI).
Future<String?> stdinAskUser(AskUserPrompt p) async {
  stdout.writeln(p.text);
  if (p.options.isNotEmpty) stdout.writeln(p.options.map((o) => '  - $o').join());
  stdout.write('> ');
  final line = stdin.readLineSync();
  return (line == null || line.trim().isEmpty) ? null : line.trim();
}

// ---------------------------------------------------------------------------
// Gate B — run-graded goal verifier (mechanical, stamps GoalVerified)
// ---------------------------------------------------------------------------

/// A resource carrying how a goal is verified by running code.
class RunGoalSpec extends Resource {
  RunGoalSpec({required this.command, this.cwd = '', this.commandByRegistry});

  /// Default check command (single-actor / legacy path).
  final List<String> command;
  final String cwd;

  /// Stage N2 multi-actor: per-actor check commands keyed by the actor's
  /// `ActorTools.registryName` (1:1 with actors in a squad). When present
  /// for the pending actor, it overrides [command]. The verifier stamps
  /// ONLY the pending actor — never every Goal actor.
  final Map<String, List<String>>? commandByRegistry;

  List<String> commandFor(String? registryName) {
    if (registryName != null) {
      final per = commandByRegistry?[registryName];
      if (per != null) return per;
    }
    return command;
  }
}

/// Mechanical verifier (schedule on [Schedules.narrative]): after a tool
/// result lands, RUN the goal's [RunGoalSpec] via the jailed `run` tool and
/// stamp [GoalVerified]. Never calls a model — the run is the terminal proof.
Future<void> runGoalVerifier(World world) async {
  final RunGoalSpec? spec;
  try {
    spec = world.getResource<RunGoalSpec>();
  } on StateError {
    return; // no run spec wired → no-op
  }

  // Stage N2: verify PER pending actor — its own registry (tools) and its
  // own check command. Stamping every Goal actor would cross-contaminate
  // verdicts in a multi-actor world.
  final registries = world.getResource<ToolRegistryResource>();
  for (final (facade, _, _, tools) in world
      .query3<Actor, ToolResultPendingMarker, ActorTools>()
      .toList()) {
    final registryName = tools.registryName;
    final runTool = registries.get(registryName)?.get(const ToolName('run'));
    if (runTool == null) continue;
    final command = spec.commandFor(registryName);
    // N2: the check runs as a REGISTERED task — canSleep() waits for
    // in-flight tasks, so the loop can never exit before a pending verdict
    // lands (the P5 flake + squad 'no verdict stamped' race).
    final taskRegistry = world.getResource<TaskRegistryResource>();
    final verifyTaskId = TaskId.create();
    taskRegistry.register(verifyTaskId, TaskHandle());
    Map<String, Object?>? map;
    try {
      final out = await runTool.execute({'command': command, 'cwd': spec.cwd});
      if (out != null) {
        if (out.startsWith('{') || out.startsWith('[')) {
          try {
            final d = jsonDecode(out);
            if (d is Map) {
              final m = <String, Object?>{};
              d.forEach((k, v) => m['$k'] = v);
              map = m;
            }
          } catch (_) {}
        } else {
          // Not JSON; treat the raw text as a single detail.
          map = {'raw': out};
        }
      }
    } finally {
      final handle = taskRegistry.take(verifyTaskId);
      if (handle != null && !handle.completer.isCompleted) {
        handle.completer.complete(null);
      }
    }
    var passed = false;
    var detail = 'run tool unavailable';
    if (map != null) {
      final ok = map['ok'] == true;
      final stderr = '${map['stderr'] ?? ''}';
      passed = ok;
      detail = ok
          ? 'run: exit=0'
          : 'run failed exit=${map['exit_code']}: $stderr';
    }
    // Stamp the run-graded verdict on THIS actor only (it bears the Goal).
    world.upsertComponent(
      facade.entity,
      GoalVerified(passed: passed, detail: detail),
    );
    world.flush();
  }
}

/// Wire the run-graded goal loop: register the spec + schedule the verifier.
void wireRunGradedGoal(
  World world, {
  required List<String> command,
  String cwd = '',
  Map<String, List<String>>? commandByRegistry,
}) {
  world.upsertResource(
    RunGoalSpec(command: command, cwd: cwd, commandByRegistry: commandByRegistry),
  );
  world
      .schedule(Schedules.narrative)
      .add(runGoalVerifier, name: 'runGradedVerifier');
  world.flush();
}

// ---------------------------------------------------------------------------
// M0b — model-proposed criteria as data (declare_check)
// ---------------------------------------------------------------------------

/// Binaries the model may propose as a check command. Deliberately narrow:
/// the model proposes, the HOST validates the shape and executes mechanically
/// — the same trust model as `intent_define` (propose as data, host
/// verifies, exit-0 decides, never self-graded).
const defaultAllowedCheckBinaries = {
  'dart', 'flutter', 'make', 'just', 'npm', 'npx', 'python3', 'cargo', 'go',
};

const _checkMetacharacters = {';', '|', '&', '`', r'$', '(', ')', '>', '<', '\n'};

/// M0b: the actor may DECLARE its own verification command as data. The
/// declared command joins [RunGoalSpec.commandByRegistry] for the actor's
/// registry — the verifier executes it mechanically; a failing exit is still
/// a failing goal. The model can never SELF-GRADE: declare only proposes.
ToolDef declareCheckTool({
  required Map<String, List<String>> declaredChecks,
  required String registryName,
  Set<String> allowedBinaries = defaultAllowedCheckBinaries,
}) {
  return ToolDef(
    name: const ToolName('declare_check'),
    description:
        'Declare the verification command for this task, e.g. '
        '"dart test" or "dart analyze lib". Allowed programs: '
        '${allowedBinaries.join(", ")}. The mechanical verifier will run the '
        'declared command; exit 0 = task done. Declare it EARLY, before '
        'you finish.',
    argsSchema: SchemaBundle(
      root: FM.object(
        'declare_check',
        properties: () => [
          FM.prop('command', FM.string()),
        ],
      ),
    ),
    execute: (args) async {
      final params = jsonDecodeMapAs(args);
      final raw = jsonDecodeString(params['command']);
      final tokens = splitCheckCommand(raw);
      if (tokens.isEmpty) {
        return 'REJECTED: empty command. Pass {"command": "<program> <args>"}.';
      }
      for (final token in tokens) {
        for (final ch in _checkMetacharacters) {
          if (token.contains(ch)) {
            return 'REJECTED: shell metacharacter "$ch" is not allowed. '
                'Declare a single plain command.';
          }
        }
      }
      if (!allowedBinaries.contains(tokens.first)) {
        return 'REJECTED: program "${tokens.first}" is not allowed. '
            'Allowed: ${allowedBinaries.join(", ")}.';
      }
      declaredChecks[registryName] = tokens;
      return 'check declared: ${tokens.join(" ")} — the mechanical '
          'verifier will run it after your changes; exit 0 = done.';
    },
  );
}

// ---------------------------------------------------------------------------
// Stage H — intent-graded goal verifier (D4: the strongest mechanical tier)
// ---------------------------------------------------------------------------

/// One scripted intent call the verifier replays: [intent] with [args] must
/// return ok and (optionally) contain every key/value in [expect].
class IntentExpectation {
  const IntentExpectation(this.intent, {this.args = const {}, this.expect = const {}});
  final String intent;
  final Map<String, dynamic> args;
  final Map<String, dynamic> expect;
}

/// Mechanical intent-graded verifier: after a tool result lands, REPLAY the
/// scripted intent calls through [IntentRuntime] and stamp [GoalVerified]
/// when every call returns ok with the expected fields. Same stamp as the
/// run-graded verifier, so `RunGradedGoalPolicy` terminates the loop
/// unchanged. The intent call is the strongest behavior oracle: typed
/// params, typed results, no stdout parsing.
Future<void> intentGoalVerifier(World world) async {
  IntentGoalSpec? spec;
  try {
    spec = world.getResource<IntentGoalSpec>();
  } on StateError {
    return; // no intent spec wired → no-op
  }
  if (world.query2<Actor, ToolResultPendingMarker>().isEmpty) return;
  // The oracle replay must start from initialState() — the SAME semantics
  // as the tier-2 dart-subprocess oracle. The model's own intent_call state
  // (IntentCallState accumulates across the run) must not leak into the
  // replay, or stateful expectations (e.g. list_saved → 2) fail spuriously.
  // The actor's state is restored after the replay so its own observations
  // stay consistent.
  final callState = world.getResource<IntentCallState>();
  final actorState = Map<String, dynamic>.of(callState.state);
  callState.state = <String, dynamic>{};
  final details = <String>[];
  var passed = true;
  for (final expectation in spec.sequence) {
    final out = await callIntent(world, name: expectation.intent, args: expectation.args);
    final ok = out['ok'] == true;
    var matches = true;
    if (ok && expectation.expect.isNotEmpty) {
      final result = (out['result'] as Map?) ?? const {};
      for (final entry in expectation.expect.entries) {
        if (result[entry.key] != entry.value) matches = false;
      }
    }
    if (!ok || !matches) {
      passed = false;
      details.add('${expectation.intent} → $out');
    } else {
      details.add('${expectation.intent} → ok');
    }
  }
  final detail = passed
      ? 'intents: all ${spec.sequence.length} calls verified'
      : 'intents failed: ${details.join('; ')}';
  callState.state = actorState; // restore the actor's own state
  // Stamp every goal-carrying actor: either a direct Goal component or an
  // ActorGoalRef backlink — GoalVerified lives on the ACTOR because
  // RunGradedGoalPolicy reads it from the decision context.
  final carriers = <Entity>{
    for (final (facade, _, _) in world.query2<Actor, Goal>().toList())
      facade.entity,
    for (final (facade, _) in world.query<ActorGoalRef>().toList())
      facade.entity,
  };
  for (final actor in carriers) {
    world.upsertComponent(actor, GoalVerified(passed: passed, detail: detail));
  }
  world.flush();
}

/// Resource carrying the intent-graded verification sequence.
class IntentGoalSpec extends Resource {
  IntentGoalSpec({required this.sequence});
  final List<IntentExpectation> sequence;
}

/// Wire the intent-graded goal loop.
void wireIntentGradedGoal(World world, {required List<IntentExpectation> sequence}) {
  world.upsertResource(IntentGoalSpec(sequence: sequence));
  world
      .schedule(Schedules.narrative)
      .add(intentGoalVerifier, name: 'intentGradedVerifier');
  world.flush();
}

// ---------------------------------------------------------------------------
// Gate B — a Goal advances by *running* code (the `run` tool), not blind edit
// ---------------------------------------------------------------------------

/// First policy in [defaultGoalFlow]: on a fresh tool result consult
/// [GoalVerified]. When the goal's own `run` (mechanical, via the jailed run
/// tool) passed, return null so the loop goes idle — the run is terminal
/// proof. When it failed, tell the actor exactly what failed and continue.
class RunGradedGoalPolicy implements DecisionPolicy {
  const RunGradedGoalPolicy();

  @override
  String get name => 'run_graded_goal';

  @override
  DecisionDraft? evaluate(DecisionContext ctx) {
    // J1.5.1: budget exhausted — stop re-prompting FOREVER. The loop
    // terminates even if the model keeps producing failing repairs.
    if (ctx.has<GoalAttemptsExhausted>()) return null;
    final verified = ctx.get<GoalVerified>();
    if (verified == null) return null;
    if (verified.passed) return null; // goal run passed — stop.

    // Monotonic failed-verification counter (never reset by prose turns —
    // this is the fix-stage endless-loop fix).
    final attempts = (ctx.get<AttemptCount>()?.value ?? 0) + 1;
    ctx.actorEntity.insert(AttemptCount(attempts));

    var maxAttempts = 3;
    try {
      maxAttempts = ctx.world.getResource<AgencyPolicy>().maxGoalAttempts;
    } on StateError {
      // no AgencyPolicy wired → conservative default
    }
    // J7: each GRANTED overseer repair cycle widens the allowance
    // monotonically (never a reset) — total attempts stay bounded by
    // base × (1 + maxCycles).
    try {
      final ledger = ctx.world.getResource<OverseerLedger>();
      maxAttempts = maxAttempts * (1 + ledger.cycles);
    } on StateError {
      // overseer not wired → base budget only
    }
    if (attempts >= maxAttempts) {
      final reason = 'goal_unverifiable: $attempts failed verification '
          'attempts (budget $maxAttempts). Last failure: ${verified.detail}';
      ctx.actorEntity
        ..insert(GoalAttemptsExhausted(reason))
        // TRANSIENT baton (one-shot, may be consumed by a racing in-flight
        // response — generation_systems clears it per turn). The DURABLE
        // terminal record is GoalAttemptsExhausted + the suspended thread;
        // hosts should key escalation ledgers off those.
        ..insert(EscalationRequest(reason: reason));
      // Suspend every thread + clear the pending trigger so no policy path
      // can re-open a decision on stale verification state (same Tier-3
      // mechanism as the loop breaker).
      final threads = ctx.actorEntity.get<ActorThreads>()?.threads ?? const [];
      for (final t in threads) {
        final (_, valid) = ctx.world.getEntity(t);
        if (valid) {
          final we = ctx.world.getEntity(t).$1;
          final status = we.get<ThreadStatus>();
          if (status != null) status.value = ThreadStatusEnum.suspended;
        }
      }
      ctx.actorEntity.remove<ToolResultPendingMarker>();
      return null;
    }

    return DecisionDraft(
      prompt:
          'Goal not verified by running code (attempt $attempts/$maxAttempts).\n'
          'Failing:\n${verified.detail}\n'
          'Fix the code so the target runs, then continue.',
    );
  }
}

/// Opens a FRESH decision on an actor: resets the per-decision ReAct round
/// budget (J1.5.2) and clears stale verification verdicts so a host-injected
/// retry (e.g. the AFM driver's repair loop) starts with a full round
/// budget instead of a silently shrunken one. Use this INSTEAD of a bare
/// `world.upsertComponent(actor, OpenDecision(...))` whenever the new
/// decision is a new task/attempt, not a ReAct continuation.
void openFreshDecision(
  World world,
  Entity actor, {
  required String prompt,
  int priority = 0,
  bool escalate = false,
  Entity? threadId,
}) {
  final we = world.getEntity(actor).$1;
  we
    ..remove<ToolRoundCount>() // fresh chain — full round budget
    ..remove<GoalVerified>() // stale verdicts must not re-trigger policies
    ..insert(
      OpenDecision(
        prompt: prompt,
        priority: priority,
        escalate: escalate,
        threadId: threadId,
      ),
    );
  // Flush immediately: the caller counts on the budget being reset when
  // this returns (the driver's repair loop runs between loop sessions).
  world.flush();
}

/// Default flow for a run-graded build. `run_graded_goal` leads so a passed
/// run terminates the loop; [ReActContinuationPolicy] is the fallback engine.
DecisionFlow defaultGoalFlow() =>
    DecisionFlow([const RunGradedGoalPolicy(), ReActContinuationPolicy()]);

// ---------------------------------------------------------------------------
// Stage D — AE-style ETL: canonical matrix rows -> goal + steps
// ---------------------------------------------------------------------------

/// One feature row of an AE-style canonical matrix (ADR 0015/0017 wire shape).
class PlanFeature {
  const PlanFeature(this.id, this.expected,
      {this.tool = 'write', this.args = const {}});
  final String id;
  final String expected;
  final String tool;
  final Map<String, dynamic> args;
}

/// Render a brief + matrix into Goal + Step components so the run-graded loop
/// can drive a build from structured planning input. Pure graph, no LLM.
void planFromMatrix(
  World world, {
  required String goalText,
  required List<PlanFeature> features,
}) {
  final goal = world.spawnComponents([Goal(text: goalText)]);
  for (final (i, f) in features.indexed) {
    world.spawnComponents([
      StepGoalLink(goal),
      StepStatus('open'),
      StepClaim('${f.id}: ${f.expected}'),
      StepAction(f.tool, {...f.args}),
      StepIndex(i),
    ]);
  }
  world.flush();
}

/// Stage G4 — AE canonical → world: the full ETL seam.
///
/// Imports a [MeaningTreeExport] (produced deterministically from an AE
/// canonical pack by `agentic_executables_wire.canonicalToMeaningTree`) into
/// the harness:
///
/// 1. the tree becomes **world state** — meaning nodes keep their canonical
///    ids (`entity.create`), so `verify_pack` tier gaps (which cite feature
///    ids) and the model's cut share ONE id vocabulary;
/// 2. feature rows render as Goal + mechanical steps (`materialize` moves),
///    so the run-graded loop (Gate B) drives the build.
///
/// Deterministic, LLM-free, no AE embed (the export is plain wire data).
void planFromSpec(
  World world, {
  required MeaningTreeExport spec,
  required String goalText,
}) {
  for (final node in spec.nodes) {
    addMeaningNode(
      world,
      kind: node.kind,
      label: node.label,
      props: node.props,
      id: node.id,
    );
  }
  for (final edge in spec.edges) {
    linkMeaning(world, from: edge.from, relation: edge.relation, to: edge.to);
  }
  final features = [
    for (final node in spec.nodes)
      if (node.kind == 'feature')
        PlanFeature(
          node.id,
          '${node.props['spec'] ?? node.label}',
          tool: 'act_with_project',
          args: {'action': 'materialize'},
        ),
  ];
  planFromMatrix(world, goalText: goalText, features: features);
}

// ---------------------------------------------------------------------------
// Stage C (a2a) — an extra actor branch in the same world (team member)
// ---------------------------------------------------------------------------

/// Spawns a *peer actor* into [world] as its own branch with its own open
/// decision. This is the a2a primitive: each member is an [Actor] entity in
/// the shared world, so a Planner + Coder (and more) can plan and build the
/// same goal, each routing to its own model/handler. Deterministic.
void spawnActorBranch(
  World world, {
  required String systemPrompt,
  required String prompt,
  AgentId? agentId,
  ModelId? modelId,
}) {
  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  world.spawnComponents([
    Actor(agentId: agentId ?? AgentId.create()),
    ActorModel(modelId: modelId ?? ModelId.create()),
    ActorSystemPrompt(text: systemPrompt),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: prompt),
  ]);
  world.flush();
}