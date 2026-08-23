import 'dart:convert';

import 'package:ecsly/ecsly.dart';

import '../../data_models/data_models.dart';
import '../../decisions/decision_flow.dart' show DeferredThinking;
import '../../events.dart';
import '../../model_router.dart';
import '../../narrative/narrative.dart';
import '../../resources/resources.dart';
import 'relevance.dart' show keywordsOf;

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
    // Deferred thinking (ADR 0005 §5): a "dream" turn gets an expanded cut —
    // doubled beat cap and budget — so the model can actually reflect over
    // more history. Still bounded; still measured like any other spend.
    var effectivePolicy = policy;
    if (entity.has<DeferredThinking>()) {
      effectivePolicy = ProjectionPolicy(
        maxBeats: policy.maxBeats * 2,
        includePartials: policy.includePartials,
        greenScreen: policy.greenScreen,
        maxProps: policy.maxProps,
        maxCoPresent: policy.maxCoPresent,
      );
    }
    final situation = buildSituation(
      world: world,
      entity: entity,
      actor: actor,
      budget: entity.has<DeferredThinking>()
          ? budget.tokens * 2
          : budget.tokens,
      policy: effectivePolicy,
      estimator: estimator,
    );
    entity.insert(situation);
  }
}

Situation buildSituation({
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
  final beats = raycastBeats(world, entity, prompt);
  final ranked = rankFragments(world, beats, prompt);
  final fit = fitToBudget(
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
  final toolSchemaCost = tools != null ? toolSchemaTokens(world, tools) : 0;
  final systemCost = systemPrompt != null ? estimator(systemPrompt.text) : 0;
  final realTokensUsed = tokensUsed + systemCost + toolSchemaCost;
  final realTruncated = truncated || realTokensUsed > budget;

  // Green-screen: explicit absences so the model knows what it does NOT see.
  final absences = <String>[];
  if (policy.greenScreen && beats.length > selected.length) {
    absences.add('${beats.length - selected.length} beat(s) are off-screen.');
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
///
/// Thread membership is read from the [FacetIndex] beatsOfThread map —
/// O(threads × beats-in-thread), not a full-world scan per thread.
List<Entity> raycastBeats(World world, WorldEntity entity, String prompt) {
  final index = world.getResource<FacetIndex>();
  final out = <Entity>{};

  final promptTerms = keywordsOf(prompt);
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
      if (!threadVisibleToWorld(world, thread, actorEntity)) continue;
      for (final beat in index.beatsOfThread(thread)) {
        // Private beats of other actors never enter another actor's cut.
        final privacy = world.getEntity(beat).$1.get<PrivateToActor>();
        if (privacy != null && privacy.actor != actorEntity) continue;
        out.add(beat);
      }
    }
  }

  return out.toList();
}

/// Whether [thread] is projectable: active/suspended/scoring only, and — when
/// a [ThreadVisibility] restricts it — only for listed agents.
bool threadVisibleToWorld(World world, Entity thread, Entity actor) {
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

/// Rank beat entities by relevance to the current [prompt].
///
/// A lightweight, deterministic heuristic: beats sharing MORE distinct terms
/// with the prompt rank higher; recency breaks ties. A single accidental term
/// match no longer outranks recency because the score is the count of matched
/// terms (not weighted 1000x over position).
List<Entity> rankFragments(World world, List<Entity> beats, String prompt) {
  final promptTerms = keywordsOf(prompt).toSet();
  if (promptTerms.isEmpty) return beats.reversed.toList();

  final scored = <(Entity, int)>[];
  for (var i = 0; i < beats.length; i++) {
    final beat = beats[i];
    final text = fragmentText(world, beat).toLowerCase();
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
({List<Entity> selected, int tokensUsed, bool truncated}) fitToBudget({
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
    final text = fragmentText(world, beat);
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

String fragmentText(World world, Entity beat) {
  final (entity, valid) = world.getEntity(beat);
  if (!valid) return '';
  final text = entity.get<TextContent>();
  return text?.text ?? '';
}

/// Estimate the token cost of the tool schemas an actor is bound to.
///
/// The model sees these schemas in its context, so they count toward the
/// real budget. Uses the default estimator (chars/4).
int toolSchemaTokens(World world, ActorTools tools) {
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
String toolResultText(ToolExecutionResult result) {
  final output = result.output;
  if (output is String) return '<result|${result.name}|$output>';
  return '<result|${result.name}|${jsonEncode(output)}>';
}

/// Human-readable projection text for a structured model output.
///
/// JSON syntax tokens (braces, quotes, key names) would flood the keyword
/// index and pollute ranking; this renders `key: value` pairs instead.
String structuredOutputText(Map<String, dynamic> output) =>
    output.entries.map((e) => '${e.key}: ${e.value}').join('; ');
