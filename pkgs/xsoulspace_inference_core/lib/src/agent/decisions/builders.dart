// ignore_for_file: lines_longer_than_80_chars

/// Declarative builders for [DecisionPolicy] — the DX surface of ADR 0005.
///
/// ```dart
/// final flow = DecisionFlow([
///   onToolResult().thenOpen(prompt: 'Tool result received. Continue.'),
///   when((c) => c.has<Goal>()).thenDream('Review progress'),
///   everyNTicks(600).thenOpen(prompt: 'Health check'),
/// ]);
/// ```
part of 'decision_flow.dart';

/// Internal trigger kinds a builder-based policy can react to.
enum _TriggerKind { toolResult, error, predicate, tickInterval }

class _BuilderPolicy implements DecisionPolicy {
  _BuilderPolicy({
    required this.name,
    required this.trigger,
    this.predicate,
    this.interval = 0,
  });

  @override
  final String name;
  final _TriggerKind trigger;
  final bool Function(DecisionContext ctx)? predicate;
  final int interval;

  DecisionDraft? Function(DecisionContext ctx)? _effect;

  /// The policy abstains until an effect is attached via then*().
  @override
  DecisionDraft? evaluate(DecisionContext ctx) {
    if (_effect == null) return null;
    if (!_fires(ctx)) return null;
    return _effect!(ctx);
  }

  bool _fires(DecisionContext ctx) => switch (trigger) {
    _TriggerKind.toolResult => ctx.has<ToolResultPendingMarker>(),
    _TriggerKind.error => ctx.has<RetryCount>(),
    _TriggerKind.tickInterval => interval > 0 && ctx.tick % interval == 0,
    _TriggerKind.predicate => predicate?.call(ctx) ?? false,
  };
}

// ── Triggers ─────────────────────────────────────────────────────────────

/// Fire when a fresh tool result is pending continuation.
_BuilderPolicy onToolResult() =>
    _BuilderPolicy(name: 'onToolResult', trigger: _TriggerKind.toolResult);

/// Fire while the actor's last response errored (retry window).
_BuilderPolicy onError() =>
    _BuilderPolicy(name: 'onError', trigger: _TriggerKind.error);

/// Fire on an arbitrary deterministic predicate.
_BuilderPolicy when(bool Function(DecisionContext ctx) predicate) =>
    _BuilderPolicy(
      name: 'when',
      trigger: _TriggerKind.predicate,
      predicate: predicate,
    );

/// Fire every [n] scene ticks (injected time; tick 0 does not fire).
_BuilderPolicy everyNTicks(int n) => _BuilderPolicy(
  name: 'everyNTicks($n)',
  trigger: _TriggerKind.tickInterval,
  interval: n,
);

// ── Effects ──────────────────────────────────────────────────────────────

extension DecisionEffect on _BuilderPolicy {
  /// Open a decision with [prompt].
  _BuilderPolicy thenOpen({
    required String prompt,
    int priority = 0,
    bool escalate = false,
    List<AgentId> shareWith = const [],
  }) {
    _effect = (_) => DecisionDraft(
      prompt: prompt,
      priority: priority,
      escalate: escalate,
      shareWith: shareWith,
    );
    return this;
  }

  /// Open a deferred-thinking ("dream") decision — projection expands the
  /// cut for this turn. Use sparingly with tiny models: it is real agency
  /// spend and shows up in precision metrics like any other decision.
  _BuilderPolicy thenDream(String prompt) {
    _effect = (_) => DecisionDraft(prompt: prompt, deferredThinking: true);
    return this;
  }

  /// Re-issue the actor's current prompt (retry-style continuation).
  _BuilderPolicy thenRetry() {
    _effect = (ctx) =>
        DecisionDraft(prompt: ctx.get<OpenDecision>()?.prompt ?? 'Retry.');
    return this;
  }
}
