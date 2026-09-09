// ignore_for_file: lines_longer_as_80_chars

/// ADR 0009 Amendment (2026-09-08) §3 — the ZERO-TOKEN MECHANICAL ACTOR.
///
/// The accelerate-and-predict behavior: while the model actor works, a
/// mechanical actor may execute a CONSENTED ready step ([ReadyStep] from
/// step_resolver.dart) — the same jailed tool surface, the same consent
/// gateway, the same beat record, ZERO model tokens. The executor is
/// INJECTED (the edit tool lives in the workspace/host packages; the
/// harness stays domain-free — the same dependency-injection the
/// task-grammar pre-pass uses for the etl ToolDef).
///
/// Laws that bind here:
/// - **Deny-by-default consent**: without an explicit host consent
///   answer the step does NOT execute — the named refusal
///   (`mechanical_actor_unconsented`) is the outcome, never a guess.
/// - **The outcome is DATA**: the tool's own result map (ok/error/failure
///   class) flows back verbatim so the frontier/beat record and the
///   step-status flip are mechanical.
/// - **One step, one execution**: the caller owns idempotence (a step
///   whose [StepStatus] is no longer `open` is never re-recorded — see
///   [recordStepOutcome]).
library;

import 'dart:convert';

import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart'
    show StepAction, StepClaimant, StepStatus, TopologyActor;
import '../narrative/narrative.dart' show Step, StepLifecycle;

/// Executes ONE consented ready step through the injected tool executor.
///
/// [editExecutor] is the tool's execute closure (e.g. the registered
/// `edit_symbol` ToolDef). [consent] is the host's deny-by-default answer
/// for THIS step's args. [toolName] is the registry tool the args are
/// legal for (bookkeeping in the outcome).
Future<Map<String, dynamic>> executeReadyStep({
  required Future<Object?> Function(Map<String, dynamic> args) editExecutor,
  required Map<String, Object?> args,
  required bool Function(Map<String, Object?> args) consent,
  String toolName = 'edit_symbol',
}) async {
  // Deny-by-default: no consent answer → the step never executes.
  if (!consent(args)) {
    return {
      'ok': false,
      'code': 'mechanical_actor_unconsented',
      'tool': toolName,
      'hint': 'the host consent gate denied this ready step — the model '
          'actor (or a human approver) owns it',
    };
  }
  final out = await editExecutor(args);
  var parsed = <String, dynamic>{};
  if (out is String) {
    try {
      final decoded = jsonDecode(out);
      if (decoded is Map<String, dynamic>) parsed = decoded;
    } on FormatException {
      // Non-JSON tool output — carried verbatim in the raw slot below.
    }
  } else if (out is Map) {
    parsed = {
      for (final e in out.entries)
        if (e.key is String) e.key as String: e.value,
    };
  }
  return {'tool': toolName, ...parsed};
}

/// Records a step outcome mechanically: flips the [Step.lifecycle] and
/// stamps the outcome data on the step entity. Pure graph logic — never
/// calls a model. A step that is no longer `open` is never re-recorded
/// (one step, one execution).
void recordStepOutcome(
  World world,
  Entity stepEntity,
  Map<String, dynamic> outcome,
) {
  final (facade, valid) = world.getEntity(stepEntity);
  if (!valid) return;
  final step = facade.get<Step>();
  if (step == null || step.status != StepLifecycle.open) return;
  final ok = outcome['ok'] == true;
  facade.insert(
    Step(
      claim: step.claim,
      verificationKind: step.verificationKind,
      status: ok ? StepLifecycle.verified : StepLifecycle.failed,
    ),
  );
  if (facade.get<StepStatus>() case final status?) {
    status.value = ok ? 'verified' : 'failed';
  } else {
    facade.insert(StepStatus(ok ? 'verified' : 'failed'));
  }
  if (facade.get<StepAction>() case final action?) {
    action.outcome = {
      'ok': ok,
      if (outcome['error'] is String) 'error': outcome['error'],
      if (outcome['failureClass'] is String)
        'failureClass': outcome['failureClass'],
    };
  }
  world.flush();
}

/// Works ONE claimed ready step AS A REGISTERED TOPOLOGY ACTOR (ADR 0009
/// Amendment §3 + worker-gradient rung 2): the accelerate-and-predict
/// behavior gated by the DECLARED topology instead of an ad-hoc actor tag.
///
/// Laws that bind here (all named, deny-by-default — never a guess):
/// - the actor must be a REGISTERED topology actor
///   (`mechanical_actor_not_registered`);
/// - the actor must DECLARE the mechanical class (`role == 'mechanical'`,
///   zero-token budget validated at registration —
///   `mechanical_actor_not_declared`);
/// - the step must carry the actor's own claim (`StepClaimant` —
///   `step_not_claimed_by_actor`), be `open`, and carry a RESOLVED
///   [StepAction] (`step_not_resolved`);
/// - the CONSENT gate is deny-by-default exactly as in
///   [executeReadyStep] — no fork, the same refusal class
///   (`mechanical_actor_unconsented`);
/// - the outcome is DATA and is recorded mechanically via
///   [recordStepOutcome] (one step, one execution).
Future<Map<String, dynamic>> workClaimedReadyStep({
  required World world,
  required Entity stepEntity,
  required Entity actorEntity,
  required Future<Object?> Function(Map<String, dynamic> args) editExecutor,
  required bool Function(Map<String, Object?> args) consent,
}) async {
  Map<String, dynamic> refusal(String code, String hint) => {
    'ok': false,
    'code': code,
    'hint': hint,
  };
  final (actorFacade, actorValid) = world.getEntity(actorEntity);
  final topo = actorValid ? actorFacade.get<TopologyActor>() : null;
  if (topo == null) {
    return refusal('mechanical_actor_not_registered',
        'the actor is not registered in the topology — register it via '
        'registerActorTopology first');
  }
  if (topo.role != 'mechanical') {
    return refusal('mechanical_actor_not_declared',
        'role "${topo.role}" does not declare the mechanical class — '
        'only role "mechanical" works ready steps with zero tokens');
  }
  final (stepFacade, stepValid) = world.getEntity(stepEntity);
  final step = stepValid ? stepFacade.get<Step>() : null;
  if (step == null) {
    return refusal('step_missing', 'the step entity does not exist');
  }
  final claimant = stepFacade.get<StepClaimant>();
  if (claimant == null || claimant.actor != actorEntity) {
    return refusal('step_not_claimed_by_actor',
        'the step is not claimed by this actor — claim it first '
        '(claimStep)');
  }
  if (step.status != StepLifecycle.open) {
    return refusal(
      'step_not_open',
      'the step is ${step.status.name} — one step, one execution',
    );
  }
  final action = stepFacade.get<StepAction>();
  if (action == null) {
    return refusal('step_not_resolved',
        'the step carries no resolved StepAction — nothing mechanical to '
        'work');
  }
  final out = await executeReadyStep(
    editExecutor: editExecutor,
    args: action.arguments,
    consent: consent,
    toolName: action.toolName,
  );
  // A denial is NOT an execution outcome: nothing ran, so the step stays
  // open (still claimed — release/steal is a named non-claim; the claim
  // ends only when the step's own lifecycle resolves it). Recording a
  // denial as `failed` would forge evidence.
  if (out['ok'] == true || out['code'] != 'mechanical_actor_unconsented') {
    recordStepOutcome(world, stepEntity, out);
  }
  return out;
}
