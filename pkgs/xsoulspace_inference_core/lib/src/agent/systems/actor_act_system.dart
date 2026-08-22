import 'dart:async';

import 'package:ecsly/ecsly.dart';

import '../../models/inference_models.dart';
import '../data_models/data_models.dart';
import '../events.dart';
import '../model_router.dart';
import '../narrative/narrative.dart';
import '../resources/resources.dart';
import 'projection/projection_systems.dart';

/// Resolve the escalated model for an actor.
///
/// Uses [ModelRouterResource] to find the lowest-tier model strictly above
/// the actor's current binding. If none is configured, falls back to the
/// actor's own model (escalation is best-effort).
ActorModel resolveEscalatedModel(World world, ActorModel current) {
  final router = world.getResource<ModelRouterResource>().router;
  final currentModel = router.models[current.modelId];
  final currentTier = currentModel?.tier ?? 0;

  Model? best;
  for (final m in router.models.values) {
    if (m.id == current.modelId) continue;
    if (m.tier <= currentTier) continue;
    if (best == null || m.tier < best.tier) best = m;
  }
  return best == null ? current : ActorModel(modelId: best.id);
}

/// Actors that hold [Agency] act.
///
/// Builds an [ActorGenerateRequest], registers an in-flight task, and
/// dispatches it to the [GenerationHandler] resolved via
/// [GenerationHandlerResource].
Future<void> actorActSystem(World world) async {
  final actorsWithAgency = world.query4<Actor, Agency, ActorModel, Situation>();
  final handlerResource = world.getResource<GenerationHandlerResource>();
  final taskRegistry = world.getResource<TaskRegistryResource>();

  for (final (entity, actor, _, model, situation) in actorsWithAgency) {
    // Never re-dispatch an actor that already has an in-flight request —
    // otherwise the schedule re-fires the same actor endlessly, flooding the
    // handler while runtime.generate is still awaiting a response.
    if (entity.has<AwaitingResponse>()) continue;

    final systemPrompt = entity.get<ActorSystemPrompt>();

    final escalate = entity.has<EscalationRequest>();
    final effectiveModel = escalate
        ? resolveEscalatedModel(world, model)
        : model;

    final toolRegistry = situation.toolRegistryName != null
        ? world.getResource<ToolRegistryResource>().get(
            situation.toolRegistryName!,
          )
        : null;

    // The projected, budget-limited context beats — the cinematic cut.
    final contextFragments = <Object>[];
    for (final beat in situation.projectedBeats) {
      final beatEntity = world.getEntity(beat);
      if (!beatEntity.$2) continue;
      final textContent = beatEntity.$1.get<TextContent>();
      if (textContent != null) {
        contextFragments.add(textContent.text);
      }
    }
    // Green-screen absences are part of the cut.
    for (final absence in situation.explicitAbsences) {
      contextFragments.add('absence:$absence');
    }

    final taskId = TaskId.create();
    taskRegistry.register(taskId, TaskHandle());

    final request = ActorGenerateRequest(
      actorEntity: entity.entity,
      agentId: actor.agentId,
      modelId: effectiveModel.modelId,
      prompt: situation.prompt,
      systemPrompt: systemPrompt?.text ?? '',
      contextFragments: contextFragments,
      schema: situation.schema,
      toolRegistry: toolRegistry,
      task: situation.schema.isEmpty
          ? InferenceTask.text
          : InferenceTask.nativelyStructuredText,
      taskId: taskId,
    );

    // Add AwaitingResponse — preserves actor state for retry on failure.
    entity.insert(AwaitingResponse(taskId: taskId));

    // Publish the request to the event channel, then fire-and-forget the
    // handler. A missing handler must fail the task immediately — otherwise
    // the actor stays in AwaitingResponse forever and the loop never sleeps.
    world.events.writer<ActorGenerateRequest>().send(request);
    final handler = handlerResource.resolve(request);
    if (handler == null) {
      taskRegistry
          .take(taskId)
          ?.completer
          .complete(
            ToolExecutionResult(
              name: 'generate',
              output: 'No generation handler',
            ),
          );
      world.events.writer<ActorGenerateResponse>().send(
        ActorGenerateResponse(
          actorEntity: entity.entity,
          structuredOutput: const {},
          rawOutput: '',
          error: 'No generation handler registered',
          taskId: taskId,
        ),
      );
      continue;
    }
    unawaited(
      handler.generate(world, request).catchError((Object e) {
        // A throwing handler must still resolve the task and free the
        // actor, or the harness hangs.
        final handle = taskRegistry.take(taskId);
        if (handle != null && !handle.completer.isCompleted) {
          handle.completer.complete(
            ToolExecutionResult(name: 'generate', output: '$e'),
          );
        }
        world.events.writer<ActorGenerateResponse>().send(
          ActorGenerateResponse(
            actorEntity: entity.entity,
            structuredOutput: const {},
            rawOutput: '',
            error: '$e',
            taskId: taskId,
          ),
        );
        return ActorGenerateResponse(
          actorEntity: entity.entity,
          structuredOutput: const {},
          rawOutput: '',
          error: '$e',
          taskId: taskId,
        );
      }),
    );
  }
}
