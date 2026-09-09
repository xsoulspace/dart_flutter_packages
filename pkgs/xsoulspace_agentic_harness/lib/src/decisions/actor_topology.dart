// ignore_for_file: lines_longer_as_80_chars

/// ACTOR TOPOLOGY AS DATA + STEP CLAIMING — worker-gradient rung 2
/// (ADR 0009 §"Planning is projection" + Amendment §3; ADR 0031 §4: actor
/// identity rides ABOVE peer identity as declared data, never as authority).
///
/// Spawn = actor registration in the world; coordination = the shared plan
/// frontier via step claiming. There is NO coordinator subsystem — ADR
/// 0009's no-planner clause applies to multi-actor exactly as it applies
/// to one actor: claims + loud bounces cover disjoint work, the frontier
/// is the one mechanism.
///
/// - **Topology as data**: `ActorTopologySpec` = `{worlds, actors:
///   [{id, role, tier, budget, toolRegistry}]}` — validated (named errors,
///   never silent fallbacks) and REGISTERED AS GRAPH DATA: each actor
///   becomes an entity carrying `TopologyActor`. Nothing here loops,
///   plans, or dispatches.
/// - **The mechanical class is a declaration**: `role == 'mechanical'`
///   declares a zero-token actor that may work CONSENTED ready steps while
///   the model actor works (deny-by-default — mechanical_actor.dart owns
///   the executor; this library owns the declaration, no fork).
/// - **Step claiming**: open step + verified dependencies + no claimant →
///   claimable by a REGISTERED topology actor. A second claim BOUNCES
///   LOUDLY: a named reason (`step_already_claimed`) carrying the current
///   claimant — never a silent merge.
/// - **Release/steal is NOT built** (named non-claim): a claim ends only
///   when the step's own lifecycle resolves it (verified/failed via the
///   mechanical actor's outcome record). No lease, no steal, no GC — the
///   first contended claim that actually needs release is the build
///   trigger (the three-failures rule).
library;

import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart'
    show Actor, StepClaimant, TopologyActor;
import '../narrative/narrative.dart' show DependsOnStep, Step, StepLifecycle;
import '../resources/resources.dart' show ToolRegistryResource;

// ─────────────────────────────────────────────────────────────
// Topology spec — pure data, no world needed to validate.
// ─────────────────────────────────────────────────────────────

/// One actor of the declared topology: `{id, role, tier, budget,
/// toolRegistry}` — the exact data shape of the topology brief.
class TopologyActorSpec {
  const TopologyActorSpec({
    required this.id,
    required this.role,
    required this.tier,
    this.budget = 0,
    this.toolRegistry,
  });

  /// Stable domain key (ADR 0031 §4: the ACTOR id — a model with a role,
  /// an agent, a human — rides above the peer/device identity).
  final String id;

  /// Declared role. `mechanical` is THE declared mechanical class
  /// (zero-token, consented ready steps only).
  final String role;

  /// Model tier (data for tier routing — never a routing engine here).
  final String tier;

  /// Token budget; a mechanical actor MUST declare 0 (the zero-token law,
  /// validated as named data).
  final int budget;

  /// Tool registry this actor acts through, resolved against
  /// `ToolRegistryResource` at registration time (unknown registry →
  /// named error).
  final String? toolRegistry;
}

/// The declared topology: `{worlds, actors}`.
class ActorTopologySpec {
  const ActorTopologySpec({required this.worlds, required this.actors});

  /// The worlds the topology spans (declared data; unique, non-empty).
  final List<String> worlds;

  /// The registered actors (unique ids, non-empty).
  final List<TopologyActorSpec> actors;
}

/// Validation failure — LOUD, named, never a silent fallback. Carries
/// every violation found (one pass, all reasons).
class TopologyValidationError implements Exception {
  TopologyValidationError(this.errors);
  final List<String> errors;

  @override
  String toString() =>
      'TopologyValidationError: ${errors.join("; ")}';
}

/// Structural validation (pure — no world needed). Returns named error
/// codes; empty list = valid. Checks: worlds non-empty + unique; actors
/// non-empty with unique non-empty ids; non-empty role/tier; non-negative
/// budget; a `mechanical` actor MUST declare budget == 0 (the zero-token
/// law as data).
List<String> validateTopologySpec(ActorTopologySpec spec) {
  final errors = <String>[];
  if (spec.worlds.isEmpty) errors.add('empty_worlds');
  final seenWorlds = <String>{};
  for (final w in spec.worlds) {
    if (w.isEmpty) {
      errors.add('empty_world_id');
    } else if (!seenWorlds.add(w)) {
      errors.add('duplicate_world:$w');
    }
  }
  if (spec.actors.isEmpty) errors.add('empty_actors');
  final seenIds = <String>{};
  for (final a in spec.actors) {
    if (a.id.isEmpty) {
      errors.add('empty_actor_id');
    } else if (!seenIds.add(a.id)) {
      errors.add('duplicate_actor_id:${a.id}');
    }
    if (a.role.isEmpty) errors.add('empty_role:${a.id}');
    if (a.tier.isEmpty) errors.add('empty_tier:${a.id}');
    if (a.budget < 0) errors.add('negative_budget:${a.id}');
    if (a.role == 'mechanical' && a.budget != 0) {
      errors.add('mechanical_actor_with_token_budget:${a.id}');
    }
  }
  return errors;
}

// ─────────────────────────────────────────────────────────────
// Registration — actors become graph data (entities), nothing else.
// ─────────────────────────────────────────────────────────────

/// Validates [spec] (structural + world cross-checks) and registers every
/// actor AS GRAPH DATA: one entity per actor carrying `TopologyActor`.
/// Throws [TopologyValidationError] (named, all violations) on any failure —
/// a partial topology is never registered.
List<Entity> registerActorTopology(World world, ActorTopologySpec spec) {
  final errors = validateTopologySpec(spec);
  final registryResource = world.maybeGetResource<ToolRegistryResource>();
  for (final a in spec.actors) {
    final registry = a.toolRegistry;
    if (registry != null &&
        registryResource != null &&
        registryResource.get(registry) == null) {
      errors.add('unknown_tool_registry:${a.id}:$registry');
    }
  }
  if (errors.isNotEmpty) throw TopologyValidationError(errors);
  final entities = <Entity>[
    for (final a in spec.actors)
      world.spawnComponents([
        TopologyActor(
          id: a.id,
          role: a.role,
          tier: a.tier,
          budget: a.budget,
          toolRegistry: a.toolRegistry,
        ),
      ]),
  ];
  world.flush();
  return entities;
}

/// The registered topology actor behind [actorEntity], or null (not
/// registered — claiming and mechanical work both refuse this honestly).
TopologyActor? topologyActorOf(World world, Entity actorEntity) {
  final (facade, valid) = world.getEntity(actorEntity);
  if (!valid) return null;
  return facade.get<TopologyActor>();
}

/// Stable display id for a claimant: the `TopologyActor.id` when the
/// claimant is a registered topology actor, else the `AgentId`, else null.
String? claimantIdOf(World world, Entity actorEntity) {
  final (facade, valid) = world.getEntity(actorEntity);
  if (!valid) return null;
  final topo = facade.get<TopologyActor>();
  if (topo != null) return topo.id;
  final actor = facade.get<Actor>();
  if (actor != null) return actor.agentId.value;
  return null;
}

// ─────────────────────────────────────────────────────────────
// Step claiming — coordination over the shared plan frontier.
// ─────────────────────────────────────────────────────────────

/// The outcome of ONE claim attempt. TOTAL (claimed) or LOUD bounce
/// (named reason) — never a silent merge, never a guess.
sealed class StepClaimResult {
  const StepClaimResult();
}

/// The claim landed: [actorId] (a registered topology actor) now holds
/// the claim on [step]; the link is the `StepClaimant` component.
class StepClaimed extends StepClaimResult {
  const StepClaimed({
    required this.step,
    required this.actor,
    required this.actorId,
  });
  final Entity step;
  final Entity actor;
  final String actorId;
}

/// The claim BOUNCED LOUDLY: [reason] is a named code and — for
/// `step_already_claimed` — [currentClaimantId] names WHO holds the claim.
/// Nothing on the step mutates on a bounce.
class StepClaimBounced extends StepClaimResult {
  const StepClaimBounced({required this.reason, this.currentClaimantId});
  final String reason;
  final String? currentClaimantId;
}

/// The exception form of the loud bounce, for callers that must not ignore
/// contention (`claimStepStrict`). Named, carrying the current claimant.
class StepClaimBounce implements Exception {
  const StepClaimBounce(this.reason, {this.currentClaimantId});
  final String reason;
  final String? currentClaimantId;

  @override
  String toString() => 'StepClaimBounce($reason'
      '${currentClaimantId == null ? "" : ", claimant: $currentClaimantId"})';
}

/// Claim [stepEntity] for [actorEntity] — the coordination primitive.
///
/// Rules (all mechanical graph logic, zero model tokens):
/// 1. the step must exist and be `open` (`step_missing` / `step_not_open`);
/// 2. no claimant may already hold it — a SECOND claim bounces LOUDLY with
///    `step_already_claimed` carrying the current claimant's id;
/// 3. every `DependsOnStep` dependency must be `verified`
///    (`dependencies_not_verified`);
/// 4. the claimant must be a REGISTERED topology actor
///    (`actor_not_in_topology`).
///
/// The claim IS the `StepClaimant` link component — no ledger, no lock
/// manager, no coordinator. Release/steal is NOT built (see library doc).
StepClaimResult claimStep(World world, Entity stepEntity, Entity actorEntity) {
  final (stepFacade, valid) = world.getEntity(stepEntity);
  if (!valid) {
    return const StepClaimBounced(reason: 'step_missing');
  }
  final step = stepFacade.get<Step>();
  if (step == null) return const StepClaimBounced(reason: 'step_missing');
  if (step.status != StepLifecycle.open) {
    return StepClaimBounced(reason: 'step_not_open:${step.status.name}');
  }

  // Loud contention check FIRST — the bounce must name the current
  // claimant even if other preconditions also fail.
  final existing = stepFacade.get<StepClaimant>();
  if (existing != null) {
    return StepClaimBounced(
      reason: 'step_already_claimed',
      currentClaimantId: claimantIdOf(world, existing.actor),
    );
  }

  for (final dependency
      in stepFacade.get<DependsOnStep>()?.dependencies ?? const <Entity>[]) {
    final (depFacade, depValid) = world.getEntity(dependency);
    final depStep = depValid ? depFacade.get<Step>() : null;
    if (depStep == null || depStep.status != StepLifecycle.verified) {
      return const StepClaimBounced(reason: 'dependencies_not_verified');
    }
  }

  final topo = topologyActorOf(world, actorEntity);
  if (topo == null) {
    return const StepClaimBounced(reason: 'actor_not_in_topology');
  }

  stepFacade.insert(StepClaimant(actorEntity));
  world.flush();
  return StepClaimed(step: stepEntity, actor: actorEntity, actorId: topo.id);
}

/// The strict form: returns the claimed step entity or THROWS
/// [StepClaimBounce] — for callers where ignoring contention would be a
/// silent merge by another name.
Entity claimStepStrict(World world, Entity stepEntity, Entity actorEntity) {
  final result = claimStep(world, stepEntity, actorEntity);
  if (result is StepClaimed) return result.step;
  final bounced = result as StepClaimBounced;
  throw StepClaimBounce(
    bounced.reason,
    currentClaimantId: bounced.currentClaimantId,
  );
}

/// Whether [stepEntity] is claimable RIGHT NOW by a registered topology
/// actor: open + verified dependencies + no claimant. The pure predicate
/// the frontier projection uses for its `claimable` field.
bool isStepClaimable(World world, Entity stepEntity) {
  final (facade, valid) = world.getEntity(stepEntity);
  if (!valid) return false;
  final step = facade.get<Step>();
  if (step == null || step.status != StepLifecycle.open) return false;
  if (facade.get<StepClaimant>() != null) return false;
  for (final dependency
      in facade.get<DependsOnStep>()?.dependencies ?? const <Entity>[]) {
    final (depFacade, depValid) = world.getEntity(dependency);
    final depStep = depValid ? depFacade.get<Step>() : null;
    if (depStep == null || depStep.status != StepLifecycle.verified) {
      return false;
    }
  }
  return true;
}
