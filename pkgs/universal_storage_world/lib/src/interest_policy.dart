/// Interest management for zone journeys (ADR 0048): which members a
/// replica wants DELIVERED, and how hosts compose that decision.
///
/// Two distinct types with deliberate shapes:
///
/// - [InterestSelection] is the WIRE form: structural and auditable —
///   explicit ids, path prefixes, or the all-members wildcard. There is
///   deliberately no predicate language on the wire; a subscriber's choice
///   must stay readable in a protocol trace.
/// - [InterestPolicy] is the HOST-side resolver: apps, games, and the
///   harness implement it over their own knowledge (sector membership,
///   entity distance, open surfaces). It is re-resolved every sync pulse,
///   so movement between zones updates the subscription without any
///   protocol change.
library;

import 'dart:collection';

/// Which members a replica currently wants delivered (ADR 0048 §2).
final class InterestSelection {
  /// The wildcard: everything (the pre-0048 behavior; also the wire
  /// back-compat default when NO subscription frame arrives).
  const InterestSelection.all()
    : all = true,
      docIds = const {},
      prefixes = const {};

  const InterestSelection.none()
    : all = false,
      docIds = const {},
      prefixes = const {};

  const InterestSelection({
    this.all = false,
    this.docIds = const {},
    this.prefixes = const {},
  });

  /// True when this is the wildcard (deliver everything).
  final bool all;

  /// Explicitly subscribed member ids.
  final Set<String> docIds;

  /// Subscribed member-id path prefixes (`'sectors/dungeon/'`).
  final Set<String> prefixes;

  /// Whether [docId] falls inside this selection.
  bool matchesDocId(final String docId) =>
      all ||
      docIds.contains(docId) ||
      prefixes.any((final prefix) => docId.startsWith(prefix));

  /// Union used by [UnionInterest].
  InterestSelection union(final InterestSelection other) => InterestSelection(
    all: all || other.all,
    docIds: {...docIds, ...other.docIds},
    prefixes: {...prefixes, ...other.prefixes},
  );

  Map<String, Object?> toJson() => {
    'all': all,
    'docs': List<String>.of(docIds)..sort(),
    'prefixes': List<String>.of(prefixes)..sort(),
  };

  static InterestSelection fromJson(final Map<String, Object?> json) {
    final docs = (json['docs'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toSet();
    final prefixes = (json['prefixes'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toSet();
    return InterestSelection(
      all: json['all'] as bool? ?? false,
      docIds: UnmodifiableSetView(docs),
      prefixes: UnmodifiableSetView(prefixes),
    );
  }

  @override
  String toString() =>
      'InterestSelection(${all ? "all" : "${docIds.length} docs, ${prefixes.length} prefixes"})';
}

/// Host-side composable resolver for an [InterestSelection] (ADR 0047 §3).
///
/// Policies are RESOLVERS, not wire predicates: a game computes spatial
/// interest from entity positions, an app computes it from open surfaces
/// and sector membership, the harness from focus. The sync layer only ever
/// sees the resolved [InterestSelection]. Implementations must be cheap and
/// synchronous — they run once per sync pulse.
abstract interface class InterestPolicy {
  /// The selection to publish on the wire RIGHT NOW.
  InterestSelection resolve();
}

/// The wildcard policy: everything (pre-0048 behavior).
final class AllInterest implements InterestPolicy {
  const AllInterest();

  @override
  InterestSelection resolve() => const InterestSelection.all();
}

/// A fixed selection — the simplest policy.
final class StaticInterestPolicy implements InterestPolicy {
  const StaticInterestPolicy(this.selection);

  final InterestSelection selection;

  @override
  InterestSelection resolve() => selection;
}

/// Subscribe to explicit member ids.
final class MemberSetInterest implements InterestPolicy {
  const MemberSetInterest(this.docIds);

  final Set<String> docIds;

  @override
  InterestSelection resolve() => InterestSelection(docIds: docIds);
}

/// Subscribe to a member-id path prefix (a whole zone/sector).
final class MemberPrefixInterest implements InterestPolicy {
  const MemberPrefixInterest(this.prefixes);

  final Set<String> prefixes;

  @override
  InterestSelection resolve() => InterestSelection(prefixes: prefixes);
}

/// Union of several policies — the composable default for "my open surfaces
/// PLUS my current zone PLUS pinned members".
final class UnionInterest implements InterestPolicy {
  const UnionInterest(this.policies);

  final List<InterestPolicy> policies;

  @override
  InterestSelection resolve() => policies.fold(
    const InterestSelection.none(),
    (final acc, final policy) => acc.union(policy.resolve()),
  );
}
