import 'dart:async';
import 'dart:convert';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import '../data_models/data_models.dart';
import '../events.dart';
import '../narrative/narrative.dart';
import '../resources/resources.dart';
import 'decision_flow_system.dart' show ToolResultPendingMarker;
import 'projection/projection_systems.dart' show toolResultText;
import 'projection/relevance.dart' show keywordsOf;

/// System 5: Execute tool calls dispatched as [ToolCallEvent]s.
///
/// Reads [ToolCallEvent]s from the event channel, executes the tools
/// via [ToolRegistryResource], and sends [ToolResultEvent]s back.
void toolExecutionSystem(World world) {
  final toolCallReader = world.events.reader<ToolCallEvent>();
  final toolResultWriter = world.events.writer<ToolResultEvent>();
  final toolRegistryResource = world.getResource<ToolRegistryResource>();
  final taskRegistry = world.getResource<TaskRegistryResource>();

  final toolCalls = toolCallReader.drain();
  world.events.channel<ToolCallEvent>().clear();

  for (final event in toolCalls) {
    final entity = world.getEntity(event.actorEntity);
    if (!entity.$2) continue;

    final (we, _) = entity;
    final tools = we.get<ActorTools>();
    final toolRegistry = tools != null
        ? toolRegistryResource.get(tools.registryName)
        : null;

    if (toolRegistry == null) {
      final result = ToolExecutionResult.encode(
        name: event.call.name.value,
        output: {'error': 'No tool registry'},
      );
      toolResultWriter.send(
        ToolResultEvent(actorEntity: event.actorEntity, result: result),
      );
      resolveToolTask(world, taskRegistry, event.taskId, result);
      continue;
    }

    // Prefer the executor resource (graph-ready, serializable definitions)
    // and fall back to the registry's inline closure.
    final executor = world.getResource<ToolExecutorResource>().get(
      event.call.name,
    );
    final toolDef = toolRegistry.get(event.call.name);
    if (executor == null && toolDef == null) {
      final result = ToolExecutionResult.encode(
        name: event.call.name.value,
        output: {'error': 'Unknown tool'},
      );
      toolResultWriter.send(
        ToolResultEvent(actorEntity: event.actorEntity, result: result),
      );
      resolveToolTask(world, taskRegistry, event.taskId, result);
      continue;
    }

    // Empty-args guard: if the call carries no arguments but the tool's
    // schema declares required properties, bounce it back to the model
    // with a self-healing error naming the missing arguments instead of
    // executing blindly (e.g. writing to the jail root because "path" was
    // dropped by an upstream decode bug).
    final requiredArgs = <String>[
      if (toolDef?.argsSchema.root case final ObjectSchema root)
        for (final prop in root.properties)
          if (!prop.isOptional) prop.name,
    ];
    if (requiredArgs.isNotEmpty && event.call.arguments.isEmpty) {
      final result = ToolExecutionResult.encode(
        name: event.call.name.value,
        output: {
          'error':
              'Tool ${event.call.name.value} called with no arguments. '
              'Required arguments: '
              '${requiredArgs.join(", ")}. '
              'Retry the call providing all required arguments.',
        },
      );
      toolResultWriter.send(
        ToolResultEvent(actorEntity: event.actorEntity, result: result),
      );
      resolveToolTask(world, taskRegistry, event.taskId, result);
      continue;
    }

    // Execute the tool. Most tools complete synchronously, but
    // async tools are handled via .then(). Errors and timeouts are converted
    // into error results so a failing tool can never dangle the actor or
    // hang the loop.
    final policy = world.getResource<AgencyPolicy>();
    unawaited(() async {
      ToolExecutionResult result;
      try {
        Future<Object?> call() => executor != null
            ? executor(event.call.arguments)
            : Future.value(toolDef!.execute(event.call.arguments));
        final value = policy.taskTimeout > Duration.zero
            ? await call().timeout(policy.taskTimeout)
            : await call();
        result = ToolExecutionResult(
          name: event.call.name.value,
          output: value is String ? value : jsonEncode(value),
        );
      } on Object catch (e) {
        result = ToolExecutionResult(
          name: event.call.name.value,
          output: jsonEncode({'error': '$e'}),
        );
      }
      toolResultWriter.send(
        ToolResultEvent(
          actorEntity: event.actorEntity,
          result: result,
          callArgs: event.call.arguments,
        ),
      );
      // Resolve the task AFTER the result event is in the channel. The
      // registry entry is what keeps [HarnessLoop.canSleep] false; resolving
      // first would let the loop exit before a final Mechanical pass turns
      // the ToolResultEvent into a beat.
      resolveToolTask(world, taskRegistry, event.taskId, result);
    }());
  }
}

void resolveToolTask(
  World world,
  TaskRegistryResource taskRegistry,
  TaskId? taskId,
  ToolExecutionResult result,
) {
  if (taskId == null) return;
  final handle = taskRegistry.take(taskId);
  if (handle != null && !handle.completer.isCompleted) {
    handle.completer.complete(result);
  }
}

/// System 6: Process tool results from [ToolResultEvent]s.
///
/// Reads [ToolResultEvent]s and stores them as Beat entities.
void processToolResultsSystem(World world) {
  final resultReader = world.events.reader<ToolResultEvent>();

  final results = resultReader.drain();
  world.events.channel<ToolResultEvent>().clear();

  for (final event in results) {
    final entity = world.getEntity(event.actorEntity);
    if (!entity.$2) continue;

    final (we, _) = entity;

    final toolBeat = world.reserveEmptyEntity().entity;
    final toolBeatEntity = world.getEntity(toolBeat).$1;
    // Structured source of truth: tool name + typed output.
    toolBeatEntity.insert(
      ToolResultContent(name: event.result.name, output: event.result.output),
    );
    // Graph provenance: which actor called this tool and with what
    // arguments — keeps the beat replayable and queryable ("what did I try
    // last time") per the graph-native memory North Star. Events are
    // transient; this is the durable record.
    toolBeatEntity.insert(Speaker(event.actorEntity));
    toolBeatEntity.insert(BeatToolCall(event.result.name, event.callArgs));
    // Short text for projection / keyword indexing only — not the source of
    // truth. The structured output lives in [ToolResultContent].
    final toolText = toolResultText(event.result);
    toolBeatEntity.insert(TextContent(toolText));
    toolBeatEntity.insert(BeatStatus(BeatStatusEnum.complete));
    toolBeatEntity.insert(BeatModality(BeatModalityEnum.toolCall));
    final attachedThread = attachBeatToActorThread(world, we, toolBeat);
    indexBeat(
      world,
      toolBeat,
      keywordsOf(toolText),
      thread: attachedThread,
    );

    // ReAct continuation (ADR 0005): mark that a fresh tool result landed.
    // The DecisionFlow (default: ReActContinuationPolicy) evaluates the
    // marker in the next AgencyGrant pass and opens the continuation
    // decision — routing is data now, not buried control flow. Bounded by
    // [AgencyPolicy.maxToolRounds] via [ToolRoundCount].
    final policy = world.getResource<AgencyPolicy>();
    final rounds = we.get<ToolRoundCount>()?.value ?? 0;
    if (!we.has<OpenDecision>() && rounds < policy.maxToolRounds) {
      we.insert(ToolRoundCount(rounds + 1));
      // Monotonic lifetime ledger (J1.5.2) — never reset, read by the
      // WorldInspector pulse and benchmark columns (K2).
      we.insert(TotalRoundCount((we.get<TotalRoundCount>()?.value ?? 0) + 1));
      we.insert(const ToolResultPendingMarker());
    }
  }
}

/// If the actor is in a thread ([ActorThreads]), attach [beat] to that
/// thread so it lives in the graph. The current decision's [OpenDecision.threadId]
/// takes precedence (targeted thread), otherwise the actor's first thread.
/// Returns the thread the beat was attached to, or null when the actor is
/// threadless — callers index the beat with this so facet-index membership
/// never desynchronizes from graph wiring (the component read-back can be
/// null pre-flush within the same mechanical tick).
Entity? attachBeatToActorThread(World world, WorldEntity actor, Entity beat) {
  final targeted = actor.get<OpenDecision>()?.threadId;
  if (targeted != null) {
    final (t, valid) = world.getEntity(targeted);
    // spawnThread stamps ThreadStatus; that's the thread-entity marker.
    if (valid && t.has<ThreadStatus>()) {
      world.getEntity(beat).$1.insert(BelongsToThread(targeted));
      return targeted;
    }
  }
  final threads = actor.get<ActorThreads>();
  if (threads == null || threads.threads.isEmpty) return null;
  final first = threads.threads.first;
  world.getEntity(beat).$1.insert(BelongsToThread(first));
  return first;
}
