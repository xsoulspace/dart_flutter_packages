// ignore_for_file: lines_longer_than_80_chars

/// DecisionFlow — public, composable decision-creation API (ADR 0005).
///
/// A [DecisionPolicy] is a pure function from world observation to an
/// optional [DecisionDraft]. Policies never mutate the world; the mechanical
/// `decisionFlowSystem` collects drafts and applies them. This makes policy
/// evaluation a plain function call — fixture state in, draft out — and
/// agency precision attributable per policy via [DecisionOrigin].
///
/// ## Where each piece is used
///
/// - **Host app / CLI** (`main`): build a [DecisionFlow], wrap it in
///   [DecisionFlowResource], `world.upsertResource(...)` — done. The harness
///   then routes decisions automatically every tick.
/// - **Tests**: evaluate policies directly against a fixture world (pure,
///   no schedules needed) or run full scenarios with a custom flow.
/// - **Metrics**: after a run, call `decisionPrecisionByPolicy(world)` to get
///   per-policy agency precision.
///
/// ## Minimal end-to-end example (host)
///
/// ```dart
/// final world = World()..addPlugin(AgentPlugin());
/// world.upsertResource(
///   DecisionFlowResource(
///     DecisionFlow([
///       // 1. ReAct: after a tool result, continue the task.
///       onToolResult().thenOpen(prompt: 'Tool result received. Continue.'),
///       // 2. Proactive: idle actor with a goal gets nudged.
///       when((c) => c.has<Goal>())
///           .thenOpen(prompt: 'Pursue your goal.'),
///       // 3. Periodic reflection ("dreaming") — costs real tokens.
///       everyNTicks(600).thenDream('Review progress; consider delegating'),
///     ]),
///   ),
/// );
/// // ... spawn scene/actors as usual; HarnessLoop routes decisions.
/// ```
library;

import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart';
import '../model_router.dart' show AgentId;
import '../narrative/components.dart';
import '../systems/decision_flow_system.dart' show ToolResultPendingMarker;

part 'builders.dart';

/// Read-only observation surface handed to policies.
///
/// Deliberately narrow: no mutation, no clocks, no I/O. Determinism is by
/// construction — the same world state yields the same evaluation.
///
/// ```dart
/// // Inside a policy's evaluate():
/// if (ctx.has<Goal>() && ctx.get<Goal>()!.text.contains('urgent')) {
///   return DecisionDraft(prompt: 'Handle the urgent goal now.', priority: 10);
/// }
/// final peers = ctx.coPresentActors(); // share decisions with these
/// ```
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

/// ```dart
/// // Escalate a stuck task to a stronger model and loop in a teammate:
/// DecisionDraft(
///   prompt: 'Task failed twice; re-plan from scratch.',
///   priority: 10,          // wins agency contention this tick
///   escalate: true,        // routed to a higher model tier
///   shareWith: [teammateId], // teammate sees this decision's context
/// )
/// ```

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
///
/// Implement this for logic the builders can't express; prefer builders for
/// common cases.
///
/// ```dart
/// class StuckTaskPolicy implements DecisionPolicy {
///   @override
///   String get name => 'stuck_task';
///
///   @override
///   DecisionDraft? evaluate(DecisionContext ctx) {
///     final retries = ctx.get<RetryCount>()?.value ?? 0;
///     if (retries < 2) return null; // not stuck yet
///     return DecisionDraft(
///       prompt: 'Multiple failures — re-plan from scratch.',
///       escalate: true,
///     );
///   }
/// }
/// ```
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

/// Resource holding the active flow. Installed by [AgentPlugin] with
/// [DecisionFlow.defaultReAct]; hosts replace it to re-route decisions.
///
/// ```dart
/// // Swap routing at runtime (e.g. user toggles "proactive mode"):
/// world.upsertResource(
///   DecisionFlowResource(DecisionFlow([
///     ReActContinuationPolicy(),
///     everyNTicks(300).thenDream('Self-review'),
///   ])),
/// );
/// ```
class DecisionFlowResource extends Resource {
  DecisionFlowResource(this.flow);
  DecisionFlow flow;
}

/// The built-in ReAct continuation: fire when the applying system has marked
/// that a fresh tool result landed and continuation budget remains.
///
/// The continuation prompt is composed from world state (latest tool result
/// for this actor) — small on-device models cannot be trusted to re-derive
/// context from projected beats alone, and a blind "continue" prompt makes
/// them loop trivial actions until the round budget burns out.
class ReActContinuationPolicy implements DecisionPolicy {
  @override
  String get name => 'react_continuation';

  @override
  DecisionDraft? evaluate(DecisionContext ctx) {
    if (!ctx.has<ToolResultPendingMarker>()) return null;
    return DecisionDraft(prompt: _continuationPrompt(ctx));
  }

  /// Latest tool-result text spoken by this actor, truncated to keep the
  /// decision prompt bounded (full output stays in the thread projection).
  static String _continuationPrompt(DecisionContext ctx) {
    final actorEntity = ctx.actorEntity.entity;
    String? lastToolText;
    String? lastToolName;
    for (final (beat, content, _, text)
        in ctx.world.query3<ToolResultContent, BeatStatus, TextContent>()) {
      final sp = beat.get<Speaker>();
      if (sp == null || sp.actor != actorEntity) continue;
      lastToolName = content.name;
      lastToolText = text.text.length > 400
          ? '${text.text.substring(0, 400)}…'
          : text.text;
    }
    final resultLine = lastToolName == null
        ? 'A tool result just arrived.'
        : 'Your `$lastToolName` tool call returned: $lastToolText';
    return '$resultLine\n\n'
        'Decide the next single step toward completing the original task: '
        'either call one more tool with concrete arguments, or — if the task '
        'is fully satisfied by the current workspace state — give the final '
        'answer. Do not repeat a tool call that already succeeded.';
  }
}
