import 'dart:convert';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import '../../data_models/data_models.dart';
import '../../decisions/decision_flow.dart' show DeferredThinking;
import '../../model_router.dart';
import '../../narrative/narrative.dart';
import '../../resources/resources.dart';
import '../decision_flow_system.dart' show ToolResultPendingMarker;
import 'cut_composition.dart';
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

  // Plan frontier (ADR 0009): unblocked open steps for the actor's goal,
  // traversed via explicit GoalLink/DependsOnStep links. When the decision
  // carries a stepId backlink only that step (plus its verified deps) is
  // projected; otherwise all open steps linked to any goal in-frame fit.
  final planProjection = projectPlanFrontier(
    world,
    decision?.stepId,
    budget: budget,
    estimator: estimator,
  );
  final planSteps = [
    for (final stepEntity in planProjection.steps)
      if (world.getEntity(stepEntity).$1.get<Step>() case final step?)
        step.claim,
  ];

  // Cinematic cut: ray-trace the graph for beats relevant to this decision.
  final beats = raycastBeats(world, entity, prompt);
  final ranked = rankFragments(world, beats, prompt);
  final absencesBuffer = <String>[];

  // ADR 0020 — when the host declares a CutComposition, the cut is a
  // composed document (typed slots, per-slot policies, input gate).
  // Absent → legacy flat ranked cut (no breaking change).
  CutCompositionResource? compositionResource;
  try {
    compositionResource = world.getResource<CutCompositionResource>();
  } on StateError {
    compositionResource = null;
  }

  var workingSet = const <String>[];
  var cutViolations = const <CutViolation>[];
  var selected = const <Entity>[];
  var truncated = false;
  var tokensUsed = 0;

  if (compositionResource != null) {
    final tools = entity.get<ActorTools>();
    final composition = compositionResource.forRegistry(tools?.registryName);
    final originalIndex = {
      for (var i = 0; i < beats.length; i++) beats[i]: i,
    };
    final goalText = entity.get<Goal>()?.text ?? prompt;
    final verdict = entity.get<GoalVerified>();
    final mapText = compositionResource.mapProvider?.call();
    final cut = composeCut(
      composition: composition,
      candidates: ranked,
      textOf: (beat) => fragmentText(world, beat),
      originalIndex: (beat) => originalIndex[beat] ?? 0,
      goalText: goalText,
      mapText: mapText,
      verdictText: verdict == null ? null : verdict.detail,
      totalCandidates: beats.length,
    );
    selected = cut.orderedBeats;
    workingSet = cut.workingSet;
    cutViolations = cut.violations;
    absencesBuffer.addAll(cut.absences);
    tokensUsed = [
      for (final beat in selected) estimator(fragmentText(world, beat)),
      for (final fragment in workingSet) estimator(fragment),
    ].fold(0, (a, b) => a + b);
    truncated = beats.length > selected.length;
  } else {
    final fit = fitToBudget(
      world: world,
      fragments: ranked,
      budget: budget,
      prompt: prompt,
      estimator: estimator,
      maxBeats: policy.maxBeats,
    );
    selected = fit.selected;
    tokensUsed = fit.tokensUsed;
    truncated = fit.truncated;
  }

  // The real context the model sees includes the system prompt and tool
  // schemas, not just the prompt + projected beats. Count them so the budget
  // metric reflects actual model input (fixes under-reporting).
  final systemPrompt = entity.get<ActorSystemPrompt>();
  final tools = entity.get<ActorTools>();
  final toolSchemaCost = tools != null ? toolSchemaTokens(world, tools) : 0;
  final systemCost = systemPrompt != null ? estimator(systemPrompt.text) : 0;
  final planCost = planSteps.fold<int>(
    0,
    (sum, claim) => sum + estimator(claim),
  );
  final realTokensUsed = tokensUsed + systemCost + toolSchemaCost + planCost;
  final realTruncated = truncated || realTokensUsed > budget;

  // Green-screen: explicit absences so the model knows what it does NOT see.
  final absences = absencesBuffer;
  if (policy.greenScreen &&
      compositionResource == null &&
      beats.length > selected.length) {
    absences.add('${beats.length - selected.length} beat(s) are off-screen.');
  }

  return Situation(
    prompt: prompt,
    schema: decision?.schema ?? SchemaBundle.empty,
    inFramePropIds: inFrameProps,
    coPresentActorIds: coPresent,
    projectedBeats: selected,
    explicitAbsences: absences,
    planSteps: planSteps,
    toolRegistryName: tools?.registryName,
    tokensUsed: realTokensUsed,
    tokenBudget: budget,
    truncated: realTruncated,
    workingSet: workingSet,
    cutViolations: cutViolations,
  );
}

/// Derived plan frontier for the actor's current decision.
///
/// Traverses explicit goal/dependency links — never keyword search — and
/// emits only unblocked steps that fit [budget]. Superseded/blocked context
/// is reported as a green-screen absence, not narrative history.
PlanProjection projectPlanFrontier(
  World world,
  Entity? stepId, {
  required int budget,
  required TokenEstimator estimator,
}) {
  final selected = <Entity>[];
  var tokensUsed = 0;
  var omitted = 0;
  final visited = <Entity>{};

  void visit(Entity entity) {
    if (!visited.add(entity)) return;
    final (facade, valid) = world.getEntity(entity);
    if (!valid) return;
    final step = facade.get<Step>();
    if (step == null || step.status != StepLifecycle.open) return;

    final dependencies =
        facade.get<DependsOnStep>()?.dependencies ?? const <Entity>[];
    for (final dependency in dependencies) {
      final (depFacade, depValid) = world.getEntity(dependency);
      if (!depValid || !visited.add(dependency)) continue;
      final depStep = depFacade.get<Step>();
      if (depStep == null || depStep.status != StepLifecycle.verified) {
        omitted++;
        return;
      }
    }

    final cost = estimator(step.claim);
    if (tokensUsed + cost > budget) {
      omitted++;
      return;
    }
    tokensUsed += cost;
    selected.add(entity);
  }

  if (stepId != null) {
    visit(stepId);
  } else {
    for (final (entity, _, _) in world.query2<GoalLink, Step>().toList()) {
      visit(entity.entity);
    }
  }
  return PlanProjection(
    steps: selected,
    tokensUsed: tokensUsed,
    tokenBudget: budget,
    truncated: omitted > 0,
    explicitAbsences: [
      if (omitted > 0) '$omitted plan step(s) are off-screen.',
    ],
  );
}

/// Mechanical step verification (ADR 0009 §2): when an actor's decision
/// carried a [OpenDecision.stepId] backlink and its tool result landed,
/// run the step's acceptance predicate as a seam-3 tool (`verify_step`)
/// and flip the [Step.lifecycle]. Pure graph logic — never calls a model.
///
/// The `verify_step` executor receives the originating call arguments and
/// returns `{passed: bool, failures?: String}`. When no executor exists the
/// step is left open — absence of proof is not failure.
Future<void> verifyStepSystem(World world) async {
  for (final (actor, _, _)
      in world.query2<Actor, ToolResultPendingMarker>().toList()) {
    final decision = actor.get<OpenDecision>();
    final stepId = decision?.stepId;
    if (stepId == null) continue;
    final (stepEntity, valid) = world.getEntity(stepId);
    if (!valid) continue;
    final step = stepEntity.get<Step>();
    if (step == null || step.status != StepLifecycle.open) continue;

    final executor = world.getResource<ToolExecutorResource>().get(
      const ToolName('verify_step'),
    );
    if (executor == null) continue;
    Object? output;
    try {
      output = await executor(step.criterionArgs);
    } on Object {
      continue; // verifier failure is data for the next tick, not fatal
    }
    if (output is String) {
      try {
        output = jsonDecode(output);
      } catch (_) {}
    }
    if (output is! Map) continue;
    final passed = output['passed'] == true;
    stepEntity.insert(
      Step(
        claim: step.claim,
        verificationKind: step.verificationKind,
        status: passed ? StepLifecycle.verified : StepLifecycle.failed,
        confidence: step.confidence,
      ),
    );
  }
  world.flush();
}

/// Budgeted result of explicit-link plan traversal.
class PlanProjection {
  const PlanProjection({
    required this.steps,
    required this.tokensUsed,
    required this.tokenBudget,
    this.truncated = false,
    this.explicitAbsences = const [],
  });
  final List<Entity> steps;
  final int tokensUsed;
  final int tokenBudget;
  final bool truncated;
  final List<String> explicitAbsences;
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
