import 'dart:async';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import '../data_models/data_models.dart';
import '../events.dart';
import '../narrative/narrative.dart';
import '../resources/resources.dart';
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
    //
    // ADR 0028 — the one-move CONTRACT is enforced in the model-facing
    // handlers (DefaultGenerationHandler for client-parsed calls,
    // WorldToolBridge for the native inline loop); this system only records
    // what they dropped as projection-visible bounce beats so the next
    // decision's cut carries the repair hint. LLM-free scripted seams and
    // the daemon's mechanical directive relay never populate
    // [droppedToolCalls] — no model, no accumulation, no contract.
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
    if (response.droppedToolCalls.isNotEmpty) {
      final executed = response.toolCalls.firstOrNull?.name.value;
      for (final dropped in response.droppedToolCalls) {
        final bounceText = oneMoveContractBounceText(
          executed: executed,
          dropped: dropped.name.value,
        );
        final bounceBeat = world.reserveEmptyEntity().entity;
        final bounceBeatEntity = world.getEntity(bounceBeat).$1;
        bounceBeatEntity.insert(
          ToolResultContent(name: dropped.name.value, output: bounceText),
        );
        bounceBeatEntity.insert(Speaker(response.actorEntity));
        bounceBeatEntity.insert(TextContent(bounceText));
        bounceBeatEntity.insert(BeatStatus(BeatStatusEnum.complete));
        bounceBeatEntity.insert(BeatModality(BeatModalityEnum.toolCall));
        final attached = attachBeatToActorThread(world, we, bounceBeat);
        indexBeat(world, bounceBeat, keywordsOf(bounceText), thread: attached);
      }
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
      // ADR 0033 §3 — the mechanical repair ladder. A WINDOW-CLASS failure
      // is never retried: the retry recomposes the same-sized cut and is
      // futile BY CONSTRUCTION (the wave md row burned ~20 retries this
      // way). The decision is DROPPED with a named outcome beat — repair
      // routes to the host ladder (converged profile / ready-move tier /
      // escalate), never back into the same cut.
      //
      // P1 (the P0 re-run finding): a FAILED generation is a SPENT round —
      // counted against [AgencyPolicy.maxToolRounds] whatever the class.
      // The 2026-09-06 budgets counted only successful tool rounds, so the
      // opaque ToolCallError class looped 59–109 failed generations
      // uncontained. When the round budget is spent the decision is DROPPED
      // (host-ladder repair), never retried into the same cut.
      final priorRounds = we.get<ToolRoundCount>()?.value ?? 0;
      if (failed) {
        we.insert(ToolRoundCount(priorRounds + 1));
      }
      final rounds = failed ? priorRounds + 1 : priorRounds;
      if (failed && isWindowClassFailure(response.error)) {
        final outcome =
            'decision_dropped: ${response.error} — the cut exceeds the '
            'model window; repair is mechanical (shrink the surface, '
            'converged profile, escalate), never a same-cut retry.';
        final dropBeat = world.reserveEmptyEntity().entity;
        final dropBeatEntity = world.getEntity(dropBeat).$1;
        dropBeatEntity.insert(TextContent(outcome));
        dropBeatEntity.insert(BeatStatus(BeatStatusEnum.complete));
        dropBeatEntity.insert(BeatModality(BeatModalityEnum.observation));
        final dropThread = attachBeatToActorThread(world, we, dropBeat);
        indexBeat(world, dropBeat, keywordsOf(outcome), thread: dropThread);
        we.remove<OpenDecision>();
      } else if (failed && isArgsInvalidFailure(response.error)) {
        // ADR 0034 amendment — the call failed the framework's schema
        // validation BEFORE reaching the host: bounce-class DATA, never a
        // same-cut retry. The named beat teaches the action-scoped slots
        // per class in the next cut (the model recovers through the
        // repair-hint loop, or the enum splits per class — a measured
        // change); the round it spent is contained by maxToolRounds.
        const outcome =
            'tool_args_invalid: the previous call failed argument '
                'validation before reaching the host. SLOTS ARE '
                'ACTION-SCOPED — dart moves take opChain/executableId '
                '(NEVER body: the model never writes code tokens); '
                'sections/keys take body/anchor; symbolId is a REQUIRED '
                'top-level slot. Re-send with every required slot.';
        final bounceBeat = world.reserveEmptyEntity().entity;
        final bounceBeatEntity = world.getEntity(bounceBeat).$1;
        // NAMED bounce beat: the tool-result slot carries the failure class
        // so projection and the repair ladder can key off it mechanically.
        bounceBeatEntity.insert(
          ToolResultContent(name: 'tool_args_invalid', output: outcome),
        );
        bounceBeatEntity.insert(TextContent(outcome));
        bounceBeatEntity.insert(BeatStatus(BeatStatusEnum.complete));
        bounceBeatEntity.insert(BeatModality(BeatModalityEnum.observation));
        final bounceThread = attachBeatToActorThread(world, we, bounceBeat);
        indexBeat(
          world,
          bounceBeat,
          keywordsOf(outcome),
          thread: bounceThread,
        );
        final maxRounds = policy.maxToolRounds;
        if (rounds >= maxRounds) {
          we.remove<OpenDecision>();
        } else {
          final prior = we.get<OpenDecision>();
          we.insert(
            OpenDecision(
              prompt: 'Error: ${response.error}. Check the '
                  'tool_args_invalid beat on your thread — re-send with '
                  'every required slot.',
              schema: prior?.schema ?? SchemaBundle.empty,
              priority: prior?.priority ?? 0,
              escalate: prior?.escalate ?? false,
              threadId: prior?.threadId,
            ),
          );
        }
      } else if (retries < policy.maxRetries && rounds < policy.maxToolRounds) {
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
