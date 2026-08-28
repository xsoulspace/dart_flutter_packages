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

import 'dart:io';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show MeaningTreeExport;
import 'package:ecsly/ecsly.dart';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, SchemaBundle, ToolDef, ToolName;

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart'
    show Actor, ActorModel, ActorSystemPrompt, DecisionContext, DecisionDraft,
        DecisionFlow, DecisionPolicy, ReActContinuationPolicy, AgentId, ModelId,
        PresentInScene, Scene, SceneFrame, OpenDecision;

import 'dart:convert';

import 'package:ecsly/ecsly.dart' show Resource, World;
import 'package:xsoulspace_agentic_harness/src/data_models/components.dart'
    show Goal, Actor, ActorGoalRef;
import 'package:xsoulspace_agentic_harness/src/meaning/intents.dart'
    show callIntent;
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_tree.dart'
    show addMeaningNode, linkMeaning;
import 'package:xsoulspace_agentic_harness/src/schedules.dart' show Schedules;
import 'package:xsoulspace_agentic_harness/src/resources/resources.dart'
    show ToolRegistryResource;
import 'package:xsoulspace_agentic_harness/src/systems/decision_flow_system.dart'
    show ToolResultPendingMarker;
import 'package:xsoulspace_agentic_harness/src/tooling/world_builder.dart'
    show GoalVerified, StepStatus, StepGoalLink, StepAction, StepClaim,
        StepIndex;

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
  RunGoalSpec({required this.command, this.cwd = ''});
  final List<String> command;
  final String cwd;
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
  final registry = world
      .getResource<ToolRegistryResource>()
      .get('default');
  final runTool = registry?.get(const ToolName('run'));
  if (runTool == null) return;

  for (final _ in world.query2<Actor, ToolResultPendingMarker>().toList()) {
    final out = await runTool.execute({'command': spec.command, 'cwd': spec.cwd});
    Map<String, Object?>? map;
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
    // Stamp the run-graded verdict on the Actor bearing the Goal.
    for (final (badge, _, _) in world.query2<Actor, Goal>().toList()) {
      world.upsertComponent(
        badge.entity,
        GoalVerified(passed: passed, detail: detail),
      );
    }
    world.flush();
    break;
  }
}

/// Wire the run-graded goal loop: register the spec + schedule the verifier.
void wireRunGradedGoal(
  World world, {
  required List<String> command,
  String cwd = '',
}) {
  world.upsertResource(RunGoalSpec(command: command, cwd: cwd));
  world
      .schedule(Schedules.narrative)
      .add(runGoalVerifier, name: 'runGradedVerifier');
  world.flush();
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
    final verified = ctx.get<GoalVerified>();
    if (verified == null) return null;
    if (verified.passed) return null; // goal run passed — stop.
    return DecisionDraft(
      prompt:
          'Goal not verified by running code.\nFailing:\n${verified.detail}\n'
          'Fix the code so the target runs, then continue.',
    );
  }
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