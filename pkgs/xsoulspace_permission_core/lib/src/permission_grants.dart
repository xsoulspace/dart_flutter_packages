import 'permission_decision.dart';
import 'permission_kind.dart';
import 'permission_request.dart';

/// One recorded allowance: kind-scoped, optionally narrowed to a
/// subject, optionally expiring. Grants are DATA a transport records
/// when a decision of scope [PermissionGrantScope.always] (or
/// [PermissionGrantScope.session]) is made — this package defines the
/// shape and the matching law, not the persistence.
final class PermissionGrant {
  const PermissionGrant({
    required this.kind,
    this.scope = PermissionGrantScope.always,
    this.subject,
    this.expiresAt,
  });

  /// The action kind this allowance covers.
  final PermissionKind kind;

  /// How far the grant carries (a [PermissionGrantScope.once] grant is
  /// single-use by store law).
  final PermissionGrantScope scope;

  /// When set, the grant covers only requests with this exact subject.
  /// `null` covers every subject of [kind].
  final String? subject;

  /// After this instant the grant matches nothing.
  final DateTime? expiresAt;

  /// Whether this grant would cover [request] (without consuming).
  /// [now] defaults to the wall clock; stores with their own clocks
  /// pass theirs so expiry stays consistent with their reads.
  bool covers(final PermissionRequest request, {final DateTime? now}) {
    if (kind != request.kind) return false;
    if (subject != null && subject != request.subject) return false;
    final expiry = expiresAt;
    if (expiry != null && (now ?? DateTime.now()).isAfter(expiry)) {
      return false;
    }
    return true;
  }

  @override
  bool operator ==(final Object other) =>
      other is PermissionGrant &&
      other.kind == kind &&
      other.scope == scope &&
      other.subject == subject &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(kind, scope, subject, expiresAt);

  @override
  String toString() =>
      'PermissionGrant(${kind.wireName}'
      '${subject == null ? '' : ', $subject'}, ${scope.name})';
}

/// Where allowances live between decisions.
///
/// The store OWNS the consumption law: reading a matching
/// [PermissionGrantScope.once] grant consumes it, so a recorded-once
/// allowance can never answer twice. Everything else is read-only
/// matching. Implementations keep the records; the contract keeps the
/// semantics.
abstract interface class PermissionGrantStore {
  /// The best matching grant for [request], consumed if it was
  /// single-use; `null` when nothing unexpired matches.
  PermissionGrant? consumeMatching(final PermissionRequest request);

  /// Records [grant]. Implementations may replace an equivalent
  /// existing grant (same kind + subject) — durability is theirs.
  void record(final PermissionGrant grant);

  /// Drops grants: all of them when every filter is null, else only
  /// the matching ones.
  void revoke({final PermissionKind? kind, final String? subject});
}

/// In-memory [PermissionGrantStore] — session lifetime, no I/O. The
/// default store for tests, CLIs and any transport whose grants die
/// with the process.
final class InMemoryPermissionGrantStore implements PermissionGrantStore {
  InMemoryPermissionGrantStore({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final List<PermissionGrant> _grants = [];

  void _dropExpired() {
    final now = _now();
    _grants.removeWhere((grant) {
      final expiry = grant.expiresAt;
      return expiry != null && now.isAfter(expiry);
    });
  }

  @override
  PermissionGrant? consumeMatching(final PermissionRequest request) {
    _dropExpired();
    for (var i = 0; i < _grants.length; i++) {
      final grant = _grants[i];
      if (grant.kind == request.kind &&
          (grant.subject == null || grant.subject == request.subject)) {
        if (grant.scope == PermissionGrantScope.once) _grants.removeAt(i);
        return grant;
      }
    }
    return null;
  }

  @override
  void record(final PermissionGrant grant) {
    // One live grant per (kind, subject) — a new decision replaces the
    // old allowance instead of accumulating shadows.
    _grants.removeWhere(
      (existing) =>
          existing.kind == grant.kind && existing.subject == grant.subject,
    );
    _grants.add(grant);
  }

  @override
  void revoke({final PermissionKind? kind, final String? subject}) {
    _grants.removeWhere(
      (grant) =>
          (kind == null || grant.kind == kind) &&
          (subject == null || grant.subject == subject),
    );
  }
}
