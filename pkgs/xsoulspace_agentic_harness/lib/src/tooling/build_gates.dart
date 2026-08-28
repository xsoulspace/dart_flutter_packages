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
    show Goal, Actor;
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