import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart';
import '../resources/resources.dart';

/// System 1: Grant agency to actors that have an [OpenDecision].
///
/// For each Actor entity with [OpenDecision] but without [Agency]
/// and without [AwaitingResponse], add the [Agency] tag.
/// This is the explicit agency-granting step — actors never assume
/// agency; systems grant it.
///
/// Prioritization: decisions with higher [OpenDecision.priority] or an
/// [EscalationRequest] are granted first. The number of concurrent grants
/// is capped by [AgencyPolicy.maxConcurrent] so a crowd of actors doesn't
/// flood the model pool.
void grantAgencySystem(World world) {
  final policy = world.getResource<AgencyPolicy>();
  final actorsWithDecisions = world.query2<Actor, OpenDecision>();

  // Collect eligible actors (have a decision, no agency, no pending response).
  final eligible = <(WorldEntity, OpenDecision)>[];
  for (final (entity, _, decision) in actorsWithDecisions) {
    if (entity.has<Agency>()) continue;
    if (entity.has<AwaitingResponse>()) continue;
    eligible.add((entity, decision));
  }

  // Sort by priority (desc), then escalation (escalated first).
  eligible.sort((a, b) {
    final byPriority = b.$2.priority.compareTo(a.$2.priority);
    if (byPriority != 0) return byPriority;
    final aEsc = a.$1.has<EscalationRequest>() || a.$2.escalate;
    final bEsc = b.$1.has<EscalationRequest>() || b.$2.escalate;
    return (bEsc ? 1 : 0).compareTo(aEsc ? 1 : 0);
  });

  // Grant up to the concurrency cap.
  var granted = 0;
  for (final (entity, decision) in eligible) {
    if (granted >= policy.maxConcurrent) break;
    entity.insert(const Agency());
    // Materialize the decision-level escalation flag as a tag so downstream
    // systems (actorAct model resolution) see it without re-reading the
    // decision — OpenDecision may be consumed before dispatch.
    if (decision.escalate && !entity.has<EscalationRequest>()) {
      entity.insert(const EscalationRequest(reason: 'decision.escalate'));
    }
    granted++;
  }
}

/// System 5b: Fail in-flight generation tasks that exceeded
/// [AgencyPolicy.taskTimeout].
///
/// Mechanical — no LLM calls. A hung backend must not dangle an actor in
/// [AwaitingResponse] forever: `canSleep()` would never be true and the loop
/// would hang. Timed-out actors get a retry decision like any other failure.
void taskTimeoutSweeperSystem(World world) {
  final policy = world.getResource<AgencyPolicy>();
  final timeout = policy.taskTimeout;
  if (timeout <= Duration.zero) return; // disabled

  final now = DateTime.now();
  final responseWriter = world.events.writer<ActorGenerateResponse>();
  final taskRegistry = world.getResource<TaskRegistryResource>();

  for (final (entity, _, awaiting)
      in world.query2<Actor, AwaitingResponse>().toList()) {
    final taskId = awaiting.taskId;
    if (taskId == null) continue;
    final handle = taskRegistry.peek(taskId);
    if (handle == null) continue; // already resolved, response pending
    if (now.difference(handle.createdAt) < timeout) continue;

    // Fail the task and emit an error response so processResponsesSystem
    // applies the normal retry path. completeError is unawaited-safe: nobody
    // may be awaiting the completer (the backend hung), so mark it handled
    // first to avoid an unhandled async error crashing the zone.
    taskRegistry.take(taskId);
    handle.completer.future.ignore();
    if (!handle.completer.isCompleted) {
      handle.completer.completeError(
        TimeoutException('generation timed out', timeout),
      );
    }
    responseWriter.send(
      ActorGenerateResponse(
        actorEntity: entity.entity,
        structuredOutput: const {},
        rawOutput: '',
        error: 'Generation timed out after ${timeout.inMilliseconds}ms',
        taskId: taskId,
      ),
    );
  }
}
