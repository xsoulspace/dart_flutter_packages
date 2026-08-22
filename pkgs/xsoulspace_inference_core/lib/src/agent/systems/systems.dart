import 'dart:async';
import 'dart:convert';

import 'package:ecsly/ecsly.dart';

import '../../models/inference_models.dart';
import '../model_router.dart';
import '../data_models/data_models.dart';
import '../events.dart';
import '../narrative.dart';
import '../resources/resources.dart';

// ─────────────────────────────────────────────
// Systems
// ─────────────────────────────────────────────

/// System 0: Seed an actor's identity into the graph as beats.
///
/// An actor's [ActorSystemPrompt] and [Goal] are its identity — "who am I / what
/// am I doing". Writing them as indexable beats in the actor's thread means
/// projection can ray-trace them on the FIRST decision, before any real beats
/// exist. This fixes the cold-start gap where projection returned nothing.
///
/// Idempotent: an actor gets identity beats exactly once (guarded by
/// [IdentityBeat]). Mechanical — never touches an LLM.
void seedIdentitySystem(World world) {
  final actors = world.query2<Actor, ActorThreads>();
  for (final (entity, _, threads) in actors.toList()) {
    // Skip actors that already have identity beats.
    if (_hasIdentityBeats(world, entity.entity)) continue;
    if (threads.threads.isEmpty) continue;

    final thread = threads.threads.first;
    final (_, valid) = world.getEntity(thread);
    if (!valid) continue;

    final systemPrompt = entity.get<ActorSystemPrompt>();
    final goal = entity.get<Goal>();
    final parts = <String>[];
    if (systemPrompt != null && systemPrompt.text.isNotEmpty) {
      parts.add(systemPrompt.text);
    }
    if (goal != null && goal.text.isNotEmpty) {
      parts.add('Goal: ${goal.text}');
    }
    if (parts.isEmpty) continue;

    final identityBeat = world.reserveEmptyEntity().entity;
    final be = world.getEntity(identityBeat).$1;
    be.insert(TextContent(parts.join('\n')));
    be.insert(BeatStatus(BeatStatusEnum.complete));
    be.insert(BeatModality(BeatModalityEnum.observation));
    be.insert(const IdentityBeat());
    be.insert(BelongsToThread(thread));
    indexBeat(world, identityBeat, _keywordsOf(parts.join(' ')));
  }
}

bool _hasIdentityBeats(World world, Entity actor) {
  // An actor has identity beats if any beat in its threads carries IdentityBeat.
  for (final (_, _, belongs, _)
      in world.query3<IdentityBeat, BelongsToThread, TextContent>()) {
    if (belongs.thread == _actorThread(world, actor)) return true;
  }
  return false;
}

Entity? _actorThread(World world, Entity actor) {
  final (e, valid) = world.getEntity(actor);
  if (!valid) return null;
  // A targeted decision routes identity to its thread.
  final targeted = e.get<OpenDecision>()?.threadId;
  if (targeted != null) return targeted;
  final threads = e.get<ActorThreads>();
  return threads?.threads.isEmpty ?? true ? null : threads!.threads.first;
}

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

/// System 2: Build a minimal [Situation] for each actor with [Agency].
///
/// Projection is ruthlessly minimal and cinematic — only props in frame,
/// co-present actors, and the local question. Context windows stay tiny.
void projectSituationSystem(World world) {
  final budget = world.getResource<ProjectionBudget>();
  final policy = world.getResource<ProjectionPolicy>();
  final estimator = budget.estimator ?? defaultTokenEstimator;

  final actorsWithAgency = world.query2<Actor, Agency>();

  // Materialize the query results before mutating, since entity.insert()
  // changes archetypes and can invalidate lazy iterators.
  for (final (entity, actor, _) in actorsWithAgency.toList()) {
    final situation = _buildSituation(
      world: world,
      entity: entity,
      actor: actor,
      budget: budget.tokens,
      policy: policy,
      estimator: estimator,
    );
    entity.insert(situation);
  }
}

Situation _buildSituation({
  required World world,
  required WorldEntity entity,
  required Actor actor,
  required int budget,
  required ProjectionPolicy policy,
  required TokenEstimator estimator,
}) {
  // Find the current scene. Multi-scene is not yet supported — fail loudly
  // instead of silently projecting against an arbitrary scene.
  WorldEntity? sceneEntity;
  for (final (sceneEnt, _, _) in world.query2<Scene, SceneFrame>()) {
    sceneEntity = sceneEnt;
    break;
  }
  if (sceneEntity == null) return Situation(tokenBudget: budget);
  assert(
    world.query2<Scene, SceneFrame>().length <= 1,
    'Multiple scenes found; multi-scene projection is not yet supported.',
  );

  // Find co-present actors (same scene, excluding self), capped.
  final coPresent = <AgentId>[];
  for (final (_, present, otherActor)
      in world.query2<PresentInScene, Actor>()) {
    if (present.sceneEntity == sceneEntity.entity &&
        otherActor.agentId != actor.agentId) {
      coPresent.add(otherActor.agentId);
      if (coPresent.length >= policy.maxCoPresent) break;
    }
  }

  // Find props in view, capped.
  final inFrameProps = <String>[];
  for (final (_, present, prop) in world.query2<PresentProp, Prop>()) {
    if (present.sceneEntity == sceneEntity.entity) {
      inFrameProps.add(prop.name);
      if (inFrameProps.length >= policy.maxProps) break;
    }
  }

  // The local question.
  final decision = entity.get<OpenDecision>();
  final prompt = decision?.prompt ?? '';

  // Cinematic cut: ray-trace the graph for beats relevant to this decision.
  final beats = _raycastBeats(world, entity, prompt);
  final ranked = _rankFragments(world, beats, prompt);
  final fit = _fitToBudget(
    world: world,
    fragments: ranked,
    budget: budget,
    prompt: prompt,
    estimator: estimator,
    maxBeats: policy.maxBeats,
  );
  final selected = fit.selected;
  final tokensUsed = fit.tokensUsed;
  final truncated = fit.truncated;

  // The real context the model sees includes the system prompt and tool
  // schemas, not just the prompt + projected beats. Count them so the budget
  // metric reflects actual model input (fixes under-reporting).
  final systemPrompt = entity.get<ActorSystemPrompt>();
  final tools = entity.get<ActorTools>();
  final toolSchemaCost = tools != null ? _toolSchemaTokens(world, tools) : 0;
  final systemCost = systemPrompt != null ? estimator(systemPrompt.text) : 0;
  final realTokensUsed = tokensUsed + systemCost + toolSchemaCost;
  final realTruncated = truncated || realTokensUsed > budget;

  // Green-screen: explicit absences so the model knows what it does NOT see.
  final absences = <String>[];
  if (policy.greenScreen) {
    if (beats.length > selected.length) {
      absences.add(
        '${beats.length - selected.length} earlier beat(s) are off-screen.',
      );
    }
    if (truncated) {
      absences.add('Some context was cut to fit the token budget.');
    }
    if (coPresent.isEmpty) {
      //noop - we dont need to if nothing is present
    }
  }

  return Situation(
    prompt: prompt,
    schema: decision?.schema ?? SchemaBundle.empty,
    inFramePropIds: inFrameProps,
    coPresentActorIds: coPresent,
    projectedBeats: selected,
    explicitAbsences: absences,
    toolRegistryName: tools?.registryName,
    tokensUsed: realTokensUsed,
    tokenBudget: budget,
    truncated: realTruncated,
  );
}

/// Ray-trace the graph for beats relevant to [prompt].
///
/// Multi-thread aware: iterates ALL of the actor's threads, skipping threads
/// that are pruned/merged/archived and threads this actor is not allowed to
/// see ([ThreadVisibility]). Private beats of other actors are excluded.
List<Entity> _raycastBeats(World world, WorldEntity entity, String prompt) {
  final index = world.getResource<FacetIndex>();
  final out = <Entity>{};

  final promptTerms = _keywordsOf(prompt);
  if (promptTerms.isNotEmpty) {
    // Privacy applies to keyword hits too — an indexed private beat must
    // never enter another actor's cut just because its keywords matched.
    for (final hit in index.beatsFor(promptTerms)) {
      final privacy = world.getEntity(hit).$1.get<PrivateToActor>();
      if (privacy != null && privacy.actor != entity.entity) continue;
      out.add(hit);
    }
  }

  // Beats reachable from the actor's thread links — every thread, not just
  // the first. Visibility and status filter what the ray may enter.
  final actorEntity = entity.entity;
  final threads = entity.get<ActorThreads>();
  if (threads != null) {
    for (final thread in threads.threads) {
      if (!_threadVisibleToWorld(world, thread, actorEntity)) continue;
      for (final (beat, belongs, _)
          in world.query2<BelongsToThread, BeatStatus>()) {
        if (belongs.thread != thread) continue;
        // Private beats of other actors never enter another actor's cut.
        final privacy = world.getEntity(beat.entity).$1.get<PrivateToActor>();
        if (privacy != null && privacy.actor != actorEntity) continue;
        out.add(beat.entity);
      }
    }
  }

  return out.toList();
}

/// Whether [thread] is projectable: active/suspended/scoring only, and — when
/// a [ThreadVisibility] restricts it — only for listed agents.
bool _threadVisibleToWorld(World world, Entity thread, Entity actor) {
  final (t, valid) = world.getEntity(thread);
  if (!valid) return false;
  final status = t.get<ThreadStatus>();
  if (status != null) {
    switch (status.value) {
      case ThreadStatusEnum.pruned:
      case ThreadStatusEnum.merged:
      case ThreadStatusEnum.archived:
        return false;
      case ThreadStatusEnum.active:
      case ThreadStatusEnum.suspended:
      case ThreadStatusEnum.scoring:
        break;
    }
  }
  final visibility = t.get<ThreadVisibility>();
  if (visibility == null || visibility.visibleTo.isEmpty) return true;
  final agentId = world.getEntity(actor).$1.get<Actor>()?.agentId;
  if (agentId == null) return false;
  return visibility.visibleTo.contains(agentId);
}

/// Common English stopwords excluded from keyword indexing/ranking — without
/// this, terms like "the" match every beat and one accidental hit beats
/// genuine relevance in the score.
const _stopwords = {
  'the',
  'and',
  'for',
  'are',
  'but',
  'not',
  'you',
  'all',
  'can',
  'her',
  'was',
  'one',
  'our',
  'out',
  'day',
  'get',
  'has',
  'him',
  'his',
  'how',
  'man',
  'new',
  'now',
  'old',
  'see',
  'two',
  'way',
  'who',
  'its',
  'did',
  'that',
  'this',
  'with',
  'have',
  'from',
  'they',
  'will',
  'would',
  'there',
  'their',
  'what',
  'about',
  'which',
  'when',
  'make',
  'like',
  'time',
  'just',
  'know',
  'take',
  'into',
  'your',
  'than',
  'then',
  'them',
  'these',
  'some',
  'could',
  'other',
  'been',
  'more',
  'also',
  'may',
  'should',
  'does',
};

/// Split [text] into lowercase keywords, dropping stopwords and short terms.
List<String> _keywordsOf(String text) => text
    .toLowerCase()
    .split(RegExp(r'\W+'))
    .where((t) => t.length > 2 && !_stopwords.contains(t))
    .toList();

/// Rank beat entities by relevance to the current [prompt].
///
/// A lightweight, deterministic heuristic: beats sharing MORE distinct terms
/// with the prompt rank higher; recency breaks ties. A single accidental term
/// match no longer outranks recency because the score is the count of matched
/// terms (not weighted 1000x over position).
List<Entity> _rankFragments(World world, List<Entity> beats, String prompt) {
  final promptTerms = _keywordsOf(prompt).toSet();
  if (promptTerms.isEmpty) return beats.reversed.toList();

  final scored = <(Entity, int)>[];
  for (var i = 0; i < beats.length; i++) {
    final beat = beats[i];
    final text = _fragmentText(world, beat).toLowerCase();
    var score = 0;
    for (final term in promptTerms) {
      if (text.contains(term)) score++;
    }
    // Relevance first (matched-term count), recency as tie-break.
    scored.add((beat, score * 100000 + i));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.map((s) => s.$1).toList();
}

/// Fit ranked beat entities into the token budget, newest-relevant first.
///
/// Returns the projected beats, used tokens, and whether anything was cut.
({List<Entity> selected, int tokensUsed, bool truncated}) _fitToBudget({
  required World world,
  required List<Entity> fragments,
  required int budget,
  required String prompt,
  required TokenEstimator estimator,
  required int maxBeats,
}) {
  final selected = <Entity>[];
  var used = estimator(prompt);
  var truncated = false;

  for (final beat in fragments) {
    if (selected.length >= maxBeats) {
      truncated = true;
      break;
    }
    final text = _fragmentText(world, beat);
    final cost = estimator(text);
    if (used + cost > budget) {
      truncated = true;
      continue;
    }
    selected.add(beat);
    used += cost;
  }

  return (selected: selected, tokensUsed: used, truncated: truncated);
}

String _fragmentText(World world, Entity beat) {
  final (entity, valid) = world.getEntity(beat);
  if (!valid) return '';
  final text = entity.get<TextContent>();
  return text?.text ?? '';
}

/// Estimate the token cost of the tool schemas an actor is bound to.
///
/// The model sees these schemas in its context, so they count toward the
/// real budget. Uses the default estimator (chars/4).
int _toolSchemaTokens(World world, ActorTools tools) {
  final registry = world.getResource<ToolRegistryResource>().get(
    tools.registryName,
  );
  if (registry == null) return 0;
  // Sum the JSON-serializable schema payloads (parameters + description).
  // Avoid jsonEncode on the whole ToolDef (ToolName isn't encodable).
  var chars = 0;
  for (final tool in registry.tools.values) {
    chars += tool.description.length;
    final json = tool.argsSchema.toJson();
    chars += jsonEncode(json).length;
  }
  return (chars / 4).ceil();
}

/// Short, projection-friendly text for a tool result beat.
///
/// The structured output lives in [ToolResultContent]; this is only a compact
/// human-readable line so the beat is keyword-indexable and projectable. It
/// is never the source of truth.
String _toolResultText(ToolExecutionResult result) {
  final output = result.output;
  if (output is String) return '<result|${result.name}|$output>';
  return '<result|${result.name}|${jsonEncode(output)}>';
}

/// Human-readable projection text for a structured model output.
///
/// JSON syntax tokens (braces, quotes, key names) would flood the keyword
/// index and pollute ranking; this renders `key: value` pairs instead.
String _structuralOutputText(Map<String, dynamic> output) =>
    output.entries.map((e) => '${e.key}: ${e.value}').join('; ');

/// Resolve the escalated model for an actor.
///
/// Uses [ModelRouterResource] to find the lowest-tier model strictly above
/// the actor's current binding. If none is configured, falls back to the
/// actor's own model (escalation is best-effort).
ActorModel _resolveEscalatedModel(World world, ActorModel current) {
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
        ? _resolveEscalatedModel(world, model)
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
          structuralOutput: const {},
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
            structuralOutput: const {},
            rawOutput: '',
            error: '$e',
            taskId: taskId,
          ),
        );
        return ActorGenerateResponse(
          actorEntity: entity.entity,
          structuralOutput: const {},
          rawOutput: '',
          error: '$e',
          taskId: taskId,
        );
      }),
    );
  }
}

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
    final responseText = response.structuralOutput.isEmpty
        ? response.rawOutput
        : _structuralOutputText(response.structuralOutput);
    responseBeatEntity.insert(TextContent(responseText));
    responseBeatEntity.insert(BeatStatus(BeatStatusEnum.complete));
    responseBeatEntity.insert(BeatModality(BeatModalityEnum.text));
    _attachBeatToActorThread(world, we, responseBeat);
    indexBeat(world, responseBeat, _keywordsOf(responseText));

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
        (response.structuralOutput.isEmpty && response.rawOutput.isEmpty)) {
      // Retry on failure/empty, but cap it so a persistently failing model
      // cannot loop forever. After [AgencyPolicy.maxRetries] the decision is
      // dropped.
      final policy = world.getResource<AgencyPolicy>();
      final retries = we.get<RetryCount>()?.value ?? 0;
      if (retries < policy.maxRetries) {
        we.insert(RetryCount(retries + 1));
        we.insert(
          OpenDecision(
            prompt: failed
                ? 'Error: ${response.error}. Retry with tighter context.'
                : 'Error: LLM returned empty response. Retry with tighter context.',
          ),
        );
      } else {
        we.remove<OpenDecision>();
      }
    } else {
      // Remove the OpenDecision — it has been resolved
      we.remove<OpenDecision>();
      we.remove<RetryCount>();
    }
    we.remove<Agency>();
    we.remove<AwaitingResponse>();
    we.remove<EscalationRequest>();

    // The turn is complete — close the streaming tap so host subscribers
    // (Flutter StreamBuilder / TUI) see an end-of-stream signal.
    unawaited(
      world.getResource<StreamingTapResource>().close(response.actorEntity),
    );
  }
}

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
      _resolveToolTask(world, taskRegistry, event.taskId, result);
      continue;
    }

    final toolDef = toolRegistry.get(event.call.name);
    if (toolDef == null) {
      final result = ToolExecutionResult.encode(
        name: event.call.name.value,
        output: {'error': 'Unknown tool'},
      );
      toolResultWriter.send(
        ToolResultEvent(actorEntity: event.actorEntity, result: result),
      );
      _resolveToolTask(world, taskRegistry, event.taskId, result);
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
        final value = policy.taskTimeout > Duration.zero
            ? await toolDef
                  .execute(event.call.arguments)
                  .timeout(policy.taskTimeout)
            : await toolDef.execute(event.call.arguments);
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
        ToolResultEvent(actorEntity: event.actorEntity, result: result),
      );
      // Resolve the task AFTER the result event is in the channel. The
      // registry entry is what keeps [HarnessLoop.canSleep] false; resolving
      // first would let the loop exit before a final Mechanical pass turns
      // the ToolResultEvent into a beat.
      _resolveToolTask(world, taskRegistry, event.taskId, result);
    }());
  }
}

void _resolveToolTask(
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
        structuralOutput: const {},
        rawOutput: '',
        error: 'Generation timed out after ${timeout.inMilliseconds}ms',
        taskId: taskId,
      ),
    );
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
    // Short text for projection / keyword indexing only — not the source of
    // truth. The structured output lives in [ToolResultContent].
    final toolText = _toolResultText(event.result);
    toolBeatEntity.insert(TextContent(toolText));
    toolBeatEntity.insert(BeatStatus(BeatStatusEnum.complete));
    toolBeatEntity.insert(BeatModality(BeatModalityEnum.toolCall));
    _attachBeatToActorThread(world, we, toolBeat);
    indexBeat(world, toolBeat, _keywordsOf(toolText));
  }
}

/// If the actor is in a thread ([ActorThreads]), attach [beat] to that
/// thread so it lives in the graph. The current decision's [OpenDecision.threadId]
/// takes precedence (targeted thread), otherwise the actor's first thread.
/// Mechanical — never a memory cache.
void _attachBeatToActorThread(World world, WorldEntity actor, Entity beat) {
  final targeted = actor.get<OpenDecision>()?.threadId;
  if (targeted != null) {
    final (t, valid) = world.getEntity(targeted);
    // spawnThread stamps ThreadStatus; that's the thread-entity marker.
    if (valid && t.has<ThreadStatus>()) {
      world.getEntity(beat).$1.insert(BelongsToThread(targeted));
      return;
    }
  }
  final threads = actor.get<ActorThreads>();
  if (threads == null || threads.threads.isEmpty) return;
  world.getEntity(beat).$1.insert(BelongsToThread(threads.threads.first));
}

/// Deliberate graph transform: summarize a set of beats into a
/// [MemorySummary] beat that stays in [thread].
///
/// This is OPTIONAL/requested — it is NOT run automatically in any schedule.
Entity summarizeThread(World world, Entity thread, List<Entity> sources) {
  final parts = <String>[];
  final keywords = <String>{};
  for (final source in sources) {
    final (entity, valid) = world.getEntity(source);
    if (!valid) continue;
    final text = entity.get<TextContent>();
    if (text != null && text.text.isNotEmpty) {
      parts.add(text.text);
    }
    keywords.addAll(_keywordsOf(entity.get<TextContent>()?.text ?? ''));
  }

  final summaryText = parts.join(' | ');
  final summaryBeat = world.reserveEmptyEntity().entity;
  final se = world.getEntity(summaryBeat).$1;
  se.insert(TextContent(summaryText));
  se.insert(BeatStatus(BeatStatusEnum.complete));
  se.insert(BeatModality(BeatModalityEnum.observation));
  se.insert(MemorySummary(summaryText));
  se.insert(BelongsToThread(thread));
  se.insert(SummarizesBeats(sources: sources));

  indexBeat(world, summaryBeat, keywords);
  return summaryBeat;
}
