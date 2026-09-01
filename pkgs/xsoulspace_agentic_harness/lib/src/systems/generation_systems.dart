import 'dart:async';

import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart';
import '../events.dart';
import '../narrative/narrative.dart';
import '../resources/resources.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'projection/projection_systems.dart';
import 'projection/relevance.dart' show keywordsOf;
import 'tool_systems.dart';

/// System 4a: Append streaming chunks to actors' [StreamingBeat]s.
///
/// Mechanical — no LLM calls. Reads [ActorGenerateStreamEvent]s and appends
/// the chunk to the target actor's partial buffer for live UI rendering.
void processStreamEventsSystem(World world) {
  final reader = world.events.reader<ActorGenerateStreamEvent>();
  final events = reader.drain();
  world.events.channel<ActorGenerateStreamEvent>().clear();

  for (final event in events) {
    final entity = world.getEntity(event.actorEntity);
    if (!entity.$2) continue;
    final (we, _) = entity;
    final streaming = we.get<StreamingBeat>() ?? StreamingBeat();
    streaming.chunks.add(event.chunk);
    we.insert(streaming);
  }
}

/// System 4: Process responses from handlers.
///
/// Mechanical — no LLM calls, no tool execution. Reads
/// [ActorGenerateResponse] events, resolves the associated task, and stores
/// them as Beat entities.
void processResponsesSystem(World world) {
  final responseReader = world.events.reader<ActorGenerateResponse>();
  final toolCallWriter = world.events.writer<ToolCallEvent>();
  final taskRegistry = world.getResource<TaskRegistryResource>();

  final responses = responseReader.drain();
  world.events.channel<ActorGenerateResponse>().clear();

  for (final response in responses) {
    // Resolve the in-flight task — the host awaiting this actor's response
    // (via TaskRegistryResource) is resumed here.
    final taskId = response.taskId;
    if (taskId != null) {
      final handle = taskRegistry.take(taskId);
      if (handle != null && !handle.completer.isCompleted) {
        handle.completer.complete(response);
      }
    }

    final entity = world.getEntity(response.actorEntity);
    if (!entity.$2) continue;

    final (we, _) = entity;

    // Store the model response as a Beat entity, then index it into the
    // facet index so projection can ray-trace to it later. Structured output
    // is rendered as readable text — JSON syntax would pollute the index.
    final responseBeat = world.reserveEmptyEntity().entity;
    final responseBeatEntity = world.getEntity(responseBeat).$1;
    final responseText = response.structuredOutput.isEmpty
        ? response.rawOutput
        : structuredOutputText(response.structuredOutput);
    responseBeatEntity.insert(TextContent(responseText));
    responseBeatEntity.insert(BeatStatus(BeatStatusEnum.complete));
    responseBeatEntity.insert(BeatModality(BeatModalityEnum.text));
    final attachedThread = attachBeatToActorThread(world, we, responseBeat);
    indexBeat(
      world,
      responseBeat,
      keywordsOf(responseText),
      thread: attachedThread,
    );

    // Dispatch parsed tool calls as ToolCallEvents for the
    // toolExecutionSystem to process. All tool results — native or parsed —
    // flow through the world's single canonical path:
    // ToolCallEvent → toolExecutionSystem → ToolResultEvent → beats.
    //
    // Each response-carried call registers a task in [TaskRegistryResource]
    // so [HarnessLoop.canSleep] stays false until the (async) execution
    // completes. Without this, runUntilIdle can exit between dispatch and
    // completion — the tool result then lands in a dead loop and is lost.
    for (final call in response.toolCalls) {
      final toolTaskId = TaskId.create();
      taskRegistry.register(toolTaskId, TaskHandle());
      toolCallWriter.send(
        ToolCallEvent(
          actorEntity: response.actorEntity,
          call: call,
          taskId: toolTaskId,
        ),
      );
    }

    // Consume Agency + AwaitingResponse + OpenDecision — actor responded.
    final failed = response.error.isNotEmpty;
    if (failed ||
        (response.structuredOutput.isEmpty && response.rawOutput.isEmpty)) {
      // Retry on failure/empty, but cap it so a persistently failing model
      // cannot loop forever. After [AgencyPolicy.maxRetries] the decision is
      // dropped. The original decision's schema/priority/thread targeting are
      // preserved — a structured decision must not silently degrade to free
      // text on retry.
      final policy = world.getResource<AgencyPolicy>();
      final retries = we.get<RetryCount>()?.value ?? 0;
      if (retries < policy.maxRetries) {
        final prior = we.get<OpenDecision>();
        we.insert(RetryCount(retries + 1));
        we.insert(
          OpenDecision(
            prompt: failed
                ? 'Error: ${response.error}. Retry with tighter context.'
                : 'Error: LLM returned empty response. '
                      'Retry with tighter context.',
            schema: prior?.schema ?? SchemaBundle.empty,
            priority: prior?.priority ?? 0,
            escalate: prior?.escalate ?? false,
            threadId: prior?.threadId,
          ),
        );
      } else {
        we.remove<OpenDecision>();
      }
    } else {
      // Remove the OpenDecision — it has been resolved
      we.remove<OpenDecision>();
      // J1.5.6 (found by the flight recorder on-device): the error-retry
      // budget survives tool-call continuations — a resolved response WITH
      // tool calls is mid-chain (ADR 0004), so a flaky backend alternating
      // "backend_failed → tool-calling response" must still exhaust the
      // SAME budget instead of resetting it every turn (unbounded retry
      // loop, 255× identical prompts live). Reset ONLY on a text-only
      // final answer, mirroring the ToolRoundCount chain semantics.
      if (response.toolCalls.isEmpty) {
        we.remove<RetryCount>();
      }
      // A final answer (no tool calls) ends the tool-round chain — reset the
      // budget so the actor's NEXT task starts fresh (ADR 0004).
      if (response.toolCalls.isEmpty) {
        we.remove<ToolRoundCount>();
      }
    }
    we.remove<Agency>();
    we.remove<AwaitingResponse>();
    we.remove<EscalationRequest>();
    // The escalation baton passed — forget the stuck marker so the next
    // loop (if any) re-triggers from a fresh streak rather than carrying a
    // stale tag forward.
    we.remove<LoopStuck>();

    // The turn is complete — close the streaming tap so host subscribers
    // (Flutter StreamBuilder / TUI) see an end-of-stream signal.
    unawaited(
      world.getResource<StreamingTapResource>().close(response.actorEntity),
    );
  }
}
