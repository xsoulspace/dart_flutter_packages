import 'dart:async';

import 'permission_decision.dart';
import 'permission_policy.dart';
import 'permission_request.dart';

/// Where an escalated request goes: the consent surface, a paired
/// peer, an OS dialog — the transport owns the route, the contract
/// owns the shape. The sink answers with the decision of the
/// authority it reached (a user picking Reject is a
/// [PermissionDeny], not an escalate).
typedef PermissionEscalationSink =
    Future<PermissionDecision> Function(PermissionRequest request);

/// The runner at the top of a permission chain.
///
/// Composition law: policies are tried in order; the first FINAL
/// decision wins; a request every policy escalated goes to the
/// [onEscalate] sink. With NO sink, an unresolved request is DENIED —
/// deny-by-default is structural here, not a policy someone must
/// remember to install: silence can never grant.
final class PermissionGate {
  const PermissionGate({required this.policies, this.onEscalate});

  /// The chain, front to back.
  final List<PermissionPolicy> policies;

  /// The authority requests land on when the whole chain escalates.
  final PermissionEscalationSink? onEscalate;

  Future<PermissionDecision> resolve(final PermissionRequest request) async {
    for (final policy in policies) {
      final decision = policy.decide(request);
      if (decision.isFinal) return decision;
    }
    final sink = onEscalate;
    if (sink == null) {
      return const PermissionDeny('unescalated — no consent authority');
    }
    return sink(request);
  }
}
