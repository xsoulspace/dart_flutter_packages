/// What a decider answers with.
///
/// Three verbs, and the third is the point of the shared contract:
/// `escalate` means "this decider does not hold the authority to
/// answer" — the request moves to the next rung (the user, a paired
/// peer, an OS dialog, a model gate) instead of being silently
/// answered. A policy that cannot decide says so; only the RUNNER at
/// the top of the chain may turn a still-escalated request into a
/// deny.
sealed class PermissionDecision {
  const PermissionDecision();

  /// Whether this decision ends the chain (allow/deny) rather than
  /// handing the request upward (escalate).
  bool get isFinal => this is! PermissionEscalate;
}

/// Granted — optionally bound to a scope (how far the allow carries).
final class PermissionAllow extends PermissionDecision {
  const PermissionAllow([this.scope = PermissionGrantScope.once]);

  /// How far this allow carries: one round-trip, the session, or
  /// durably (recorded in a grant store by the transport).
  final PermissionGrantScope scope;

  @override
  bool operator ==(final Object other) =>
      other is PermissionAllow && other.scope == scope;

  @override
  int get hashCode => scope.hashCode;

  @override
  String toString() => 'PermissionAllow(${scope.name})';
}

/// Refused — with an honest, recordable reason.
final class PermissionDeny extends PermissionDecision {
  const PermissionDeny([this.reason]);

  /// Why the action is refused (audit lines render this verbatim).
  final String? reason;

  @override
  bool operator ==(final Object other) =>
      other is PermissionDeny && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() =>
      reason == null ? 'PermissionDeny()' : 'PermissionDeny($reason)';
}

/// Undecided HERE — the requesting transport must find a higher
/// authority. Escalate is NOT a soft deny: it carries no verdict, and
/// a chain that ends on it without a sink is a deny exactly because
/// deny-by-default is the only sound silence.
final class PermissionEscalate extends PermissionDecision {
  const PermissionEscalate({this.to, this.reason});

  /// Audience hint for the next rung ('user', 'paired-peer', 'os',
  /// 'model-gate' — free-form; transports route, this only orients).
  final String? to;

  /// Why this decider stepped aside.
  final String? reason;

  @override
  bool operator ==(final Object other) =>
      other is PermissionEscalate && other.to == to && other.reason == reason;

  @override
  int get hashCode => Object.hash(to, reason);

  @override
  String toString() =>
      'PermissionEscalate(to: ${to ?? 'next'}, '
      'reason: ${reason ?? 'unspecified'})';
}

/// How far an allow carries.
enum PermissionGrantScope {
  /// This round-trip only — never recorded.
  once,

  /// Until the session (or transport lifetime) ends.
  session,

  /// Durably, in a [PermissionGrantStore] the transport owns.
  always,
}
