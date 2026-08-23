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

/// Marker written by processToolResultsSystem when a fresh tool result landed
/// and continuation budget remains; consumed (cleared) here each tick.
class ToolResultPendingMarker implements Component {
  const ToolResultPendingMarker();
}

/// Evaluate the active [DecisionFlow] for every actor and apply drafts.
void decisionFlowSystem(World world) {
  final resource = world.getResource<DecisionFlowResource>();
  var tick = 0;
  for (final (_, _, scene) in world.query2<Scene, SceneFrame>()) {
    tick = scene.frame;
    break;
  }

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
  }

  // Clear one-shot trigger markers after evaluation.
  for (final (entity, _, _)
      in world.query2<Actor, ToolResultPendingMarker>().toList()) {
    entity.remove<ToolResultPendingMarker>();
  }
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
  for (final (entity, _, origin, _)
      in world.query3<Actor, DecisionOrigin, Actor>().toList()) {
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
