// ignore_for_file: lines_longer_than_80_chars

/// DecisionFlow — public, composable decision-creation API (ADR 0005).
///
/// A [DecisionPolicy] is a pure function from world observation to an
/// optional [DecisionDraft]. Policies never mutate the world; the mechanical
/// `decisionFlowSystem` collects drafts and applies them. This makes policy
/// evaluation a plain function call — fixture state in, draft out — and
/// agency precision attributable per policy via [DecisionOrigin].
library;

import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart';
import '../model_router.dart' show AgentId;
import '../systems/decision_flow_system.dart' show ToolResultPendingMarker;

part 'builders.dart';

/// Read-only observation surface handed to policies.
///
/// Deliberately narrow: no mutation, no clocks, no I/O. Determinism is by
/// construction — the same world state yields the same evaluation.
class DecisionContext {
  DecisionContext({
    required this.actor,
    required this.world,
    required this.tick,
  });

  /// The actor entity being evaluated.
  final Entity actor;
  final World world;

  /// Current scene frame (injected time — never DateTime.now()).
  final int tick;

  WorldEntity get actorEntity => world.getEntity(actor).$1;

  bool has<T extends Component>() => actorEntity.has<T>();

  T? get<T extends Component>() => actorEntity.get<T>();

  /// Agent ids of other actors in any scene (co-presence refinement later).
  List<AgentId> coPresentActors() {
    final self = actorEntity.get<Actor>()?.agentId;
    return [
      for (final (_, _, actor) in world.query2<PresentInScene, Actor>())
        if (actor.agentId != self) actor.agentId,
    ];
  }
}

/// A decision a policy wants opened. Pure data.
class DecisionDraft {
  const DecisionDraft({
    required this.prompt,
    this.priority = 0,
    this.escalate = false,
    this.deferredThinking = false,
    this.shareWith = const [],
  });

  final String prompt;
  final int priority;

  /// Route to a stronger model tier.
  final bool escalate;

  /// Tag as deliberate second-pass thinking — projection expands the cut.
  final bool deferredThinking;

  /// Agent ids that should receive a shared copy of this decision's context.
  final List<AgentId> shareWith;
}

/// Marker: which policy created this actor's current decision. Written by
/// the applying system; read by metrics for per-policy agency precision.
class DecisionOrigin implements Component {
  const DecisionOrigin(this.policyName);
  final String policyName;
}

/// Marker: this decision is deliberate deferred thinking ("dreaming").
/// Projection may expand the cut for turns carrying it.
class DeferredThinking implements Component {
  const DeferredThinking();
}

/// A named, deterministic decision-creation rule.
abstract class DecisionPolicy {
  String get name;

  /// Return a [DecisionDraft] to open on [ctx.actor], or null to abstain.
  /// Must be deterministic and side-effect free.
  DecisionDraft? evaluate(DecisionContext ctx);
}

/// An ordered set of policies. First non-null draft wins per actor per tick.
class DecisionFlow {
  const DecisionFlow(this.policies);

  final List<DecisionPolicy> policies;

  /// The default harness flow: ReAct tool-result continuation (ADR 0005 §4),
  /// preserving pre-API behavior including maxToolRounds bounding.
  static DecisionFlow defaultReAct() =>
      DecisionFlow([ReActContinuationPolicy()]);

  /// Evaluate all policies against [ctx]; return the first non-null draft
  /// with its policy name, or null.
  ({String policyName, DecisionDraft draft})? evaluate(DecisionContext ctx) {
    for (final policy in policies) {
      final draft = policy.evaluate(ctx);
      if (draft != null) return (policyName: policy.name, draft: draft);
    }
    return null;
  }
}

/// Resource holding the active flow. Hosts replace it to re-route decisions;
/// tests swap it per scenario.
class DecisionFlowResource extends Resource {
  DecisionFlowResource(this.flow);
  DecisionFlow flow;
}

/// The built-in ReAct continuation: fire when the applying system has marked
/// that a fresh tool result landed and continuation budget remains.
class ReActContinuationPolicy implements DecisionPolicy {
  @override
  String get name => 'react_continuation';

  @override
  DecisionDraft? evaluate(DecisionContext ctx) =>
      ctx.has<ToolResultPendingMarker>()
      ? const DecisionDraft(prompt: 'Tool result received. Continue the task.')
      : null;
}
