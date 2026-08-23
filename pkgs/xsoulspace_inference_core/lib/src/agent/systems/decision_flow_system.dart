// ignore_for_file: lines_longer_than_80_chars

/// Mechanical application of [DecisionFlow] drafts (ADR 0005).
///
/// Runs in the AgencyGrant schedule BEFORE grantAgencySystem: it observes
/// pending triggers, evaluates the flow, opens decisions, and stamps
/// [DecisionOrigin] so agency precision is attributable per policy.
library;

import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart';
import '../decisions/decision_flow.dart';
import '../model_router.dart' show AgentId;
import '../narrative/narrative.dart';
import 'projection/relevance.dart' show keywordsOf;

/// Marker written by processToolResultsSystem when a fresh tool result landed
/// and continuation budget remains; consumed (cleared) here each tick.
class ToolResultPendingMarker implements Component {
  const ToolResultPendingMarker();
}

/// Evaluate the active [DecisionFlow] for every actor and apply drafts.
void decisionFlowSystem(World world) {
  final resource = world.getResource<DecisionFlowResource>();
  // Injected time: HarnessLoop advances this every tick via
  // syncScheduleExecutionFrame — deterministic, no wall clock.
  final tick = world.getResource<ScheduleExecutionPolicyResource>().frameId;

  for (final (entity, _, _) in world.query2<Actor, ActorModel>().toList()) {
    // Never stack a mechanical decision on top of an existing one.
    if (entity.has<OpenDecision>()) continue;
    if (entity.has<Agency>() || entity.has<AwaitingResponse>()) continue;

    final ctx = DecisionContext(actor: entity.entity, world: world, tick: tick);
    final result = resource.flow.evaluate(ctx);
    if (result == null) continue;

    final draft = result.draft;
    entity.insert(
      OpenDecision(
        prompt: draft.prompt,
        priority: draft.priority,
        escalate: draft.escalate,
      ),
    );
    entity.insert(DecisionOrigin(result.policyName));
    if (draft.deferredThinking) entity.insert(const DeferredThinking());

    // Sharing (ADR 0005 §6): write an addressed notification beat into each
    // target actor's thread so their next projection ray-traces it. The
    // beat is graph content under existing visibility rules — no special
    // channel, nothing new to invariant-check.
    for (final targetId in draft.shareWith) {
      _shareDecisionBeat(world, entity.entity, draft.prompt, targetId);
    }
  }

  // Clear one-shot trigger markers after evaluation.
  for (final (entity, _, _)
      in world.query2<Actor, ToolResultPendingMarker>().toList()) {
    entity.remove<ToolResultPendingMarker>();
  }
}

/// Write a shared decision beat into [targetId]'s first thread.
void _shareDecisionBeat(
  World world,
  Entity originActor,
  String prompt,
  AgentId targetId,
) {
  // Resolve the target actor entity by agent id.
  Entity? target;
  for (final (entity, _, actor) in world.query2<PresentInScene, Actor>()) {
    if (actor.agentId == targetId) {
      target = entity.entity;
      break;
    }
  }
  if (target == null) return;

  final targetEntity = world.getEntity(target).$1;
  final threads = targetEntity.get<ActorThreads>();
  if (threads == null || threads.threads.isEmpty) return;
  final thread = threads.threads.first;

  final beat = world.reserveEmptyEntity().entity;
  final be = world.getEntity(beat).$1;
  be.insert(TextContent('Shared decision from a peer: $prompt'));
  be.insert(BeatStatus(BeatStatusEnum.complete));
  be.insert(BeatModality(BeatModalityEnum.observation));
  be.insert(Speaker(originActor));
  be.insert(BelongsToThread(thread));
  be.insert(AddressedTo(target));
  indexBeat(
    world,
    beat,
    keywordsOf('Shared decision from a peer: $prompt'),
    thread: thread,
  );
}

/// Per-policy agency precision from a finished run's world state.
///
/// precision(p) = decisions from p that produced a response beat / all
/// decisions from p. Call after runUntilIdle; decisions still open count
/// against precision (they have not yet produced value).
Map<String, ({int created, int answered})> decisionPrecisionByPolicy(
  World world,
) {
  final stats = <String, ({int created, int answered})>{};
  for (final record in world.query2<Actor, DecisionOrigin>().toList()) {
    final entity = record.$1;
    final origin = record.$3;
    void bump(String name, {required bool answered}) {
      final cur = stats[name] ?? (created: 0, answered: 0);
      stats[name] = (
        created: cur.created + 1,
        answered: cur.answered + (answered ? 1 : 0),
      );
    }

    // The origin persists on the actor; an actor whose last decision was
    // resolved has no OpenDecision — treat "no OpenDecision" as answered.
    final answered = !entity.has<OpenDecision>();
    bump(origin.policyName, answered: answered);
  }
  return stats;
}
