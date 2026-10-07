import 'permission_decision.dart';
import 'permission_grants.dart';
import 'permission_kind.dart';
import 'permission_policy.dart';
import 'permission_request.dart';

/// Allow everything, at one scope. The Full-Access/YOLO stance.
final class AllowAllPolicy implements PermissionPolicy {
  const AllowAllPolicy([this.scope = PermissionGrantScope.once]);

  /// How far each allow carries.
  final PermissionGrantScope scope;

  @override
  PermissionDecision decide(final PermissionRequest request) =>
      PermissionAllow(scope);
}

/// Allow exactly the listed kinds; anything else falls to [otherwise]
/// (escalate by default — an unlisted kind is an undecided kind, not a
/// denied one).
final class KindAllowlistPolicy implements PermissionPolicy {
  const KindAllowlistPolicy({
    required this.allowed,
    this.otherwise = const PermissionEscalate(to: 'user'),
  });

  /// Kinds answered without the consent surface.
  final Set<PermissionKind> allowed;

  /// The decision for kinds outside [allowed].
  final PermissionDecision otherwise;

  @override
  PermissionDecision decide(final PermissionRequest request) =>
      allowed.contains(request.kind) ? const PermissionAllow() : otherwise;
}

/// Answer from previously-recorded grants: a matching, unexpired grant
/// allows (at the granted scope), anything else escalates. A `once`
/// grant is CONSUMED on the answer that uses it — single-use by
/// construction, so a recorded-once grant can never allow twice.
final class GrantPolicy implements PermissionPolicy {
  const GrantPolicy(this.store);

  final PermissionGrantStore store;

  @override
  PermissionDecision decide(final PermissionRequest request) {
    final grant = store.consumeMatching(request);
    if (grant == null) {
      return const PermissionEscalate(to: 'user', reason: 'no grant');
    }
    return PermissionAllow(grant.scope);
  }
}

/// Run policies in order; the first FINAL decision wins. All-escalate
/// composes into one escalate — the chain itself did not decide, and
/// says so upward instead of inventing a verdict.
final class FirstMatchPolicy implements PermissionPolicy {
  const FirstMatchPolicy(this.policies);

  /// Tried front to back; later policies see only requests the earlier
  /// ones escalated.
  final List<PermissionPolicy> policies;

  @override
  PermissionDecision decide(final PermissionRequest request) {
    for (final policy in policies) {
      final decision = policy.decide(request);
      if (decision.isFinal) return decision;
    }
    return const PermissionEscalate(to: 'user', reason: 'no policy decided');
  }
}
