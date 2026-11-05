/// Probe-set bookkeeping for the weightmap validation program.
///
/// PROGRAM.md §3 law: every edit is validated against THREE DISJOINT probe
/// sets — localization / certification / generalization. Overlap is a REFUSE,
/// not a warning: a probe that both localized an edit and certifies it is a
/// circular claim. Duplicate digests within one set are refused for the same
/// reason (a double-counted probe inflates its own denominator).
///
/// Cells are referenced by frozen G-cell NAME ([CellRef], strings only).
/// This package must NOT depend on engine packages (mlx_native): the name is
/// the contract; cell definitions live with the frozen oracle, not here.
library;

/// A reference to a frozen G-cell by name (e.g. `G2-loop-rate`).
///
/// Strings only by design — see the library doc. Value-typed so cell refs can
/// be compared and used as map keys without identity accidents.
final class CellRef {
  const CellRef(this.name);

  /// The frozen G-cell name. Freezing (and the name list) is a PREREG-A A4
  /// artifact; this type deliberately carries nothing else.
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CellRef && other.name == name);

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'CellRef($name)';
}

/// The three per-edit probe sets, as lists of probe digests.
///
/// Lists are treated as read-only by [ProbeBookkeeping]; the constructor does
/// not copy, so callers must not mutate a list after handing it over.
final class ProbeSet {
  const ProbeSet({
    required this.localization,
    required this.certification,
    required this.generalization,
  });

  /// Probes used to LOCATE the edit (attribution, direction proposals).
  final List<String> localization;

  /// Probes used to CERTIFY the edit (the frozen G-cell verdicts).
  final List<String> certification;

  /// Held-out probes used to test GENERALIZATION (never seen by the proposer).
  final List<String> generalization;
}

/// A NAMED refusal from [ProbeBookkeeping.assertDisjoint].
///
/// [code] is one of:
/// - `PROBE_OVERLAP` — two of the three sets share at least one digest
///   (`detail` names the pair and the shared digests);
/// - `DUP_IN_SET` — one set contains the same digest twice (`detail` names
///   the set and the duplicated digests).
///
/// Errors are named, never silent: [toString] always starts with the code.
final class ProbeSetViolation implements Exception {
  const ProbeSetViolation(this.code, this.detail);

  /// Machine-readable refusal code (`PROBE_OVERLAP` or `DUP_IN_SET`).
  final String code;

  /// Human-readable detail: which sets, which digests.
  final String detail;

  @override
  String toString() => '$code: $detail';
}

/// Disjointness enforcement for [ProbeSet]. Namespace-only class.
abstract final class ProbeBookkeeping {
  /// Refuses (throws [ProbeSetViolation]) unless the three sets are pairwise
  /// disjoint and duplicate-free; returns normally ("ok") otherwise.
  ///
  /// Check order is part of the contract: `DUP_IN_SET` (within each set, in
  /// declaration order) is checked BEFORE `PROBE_OVERLAP` (pairwise, in the
  /// order localization-certification, localization-generalization,
  /// certification-generalization), so a bookkeeping error in one set is
  /// never masked by a cross-set symptom.
  static void assertDisjoint(ProbeSet set) {
    _assertNoDuplicates('localization', set.localization);
    _assertNoDuplicates('certification', set.certification);
    _assertNoDuplicates('generalization', set.generalization);
    _assertNoOverlap(
      'localization',
      set.localization,
      'certification',
      set.certification,
    );
    _assertNoOverlap(
      'localization',
      set.localization,
      'generalization',
      set.generalization,
    );
    _assertNoOverlap(
      'certification',
      set.certification,
      'generalization',
      set.generalization,
    );
  }

  static void _assertNoDuplicates(String setName, List<String> digests) {
    final seen = <String>{};
    final dups = <String>{};
    for (final d in digests) {
      if (!seen.add(d)) dups.add(d);
    }
    if (dups.isNotEmpty) {
      final sorted = dups.toList()..sort();
      throw ProbeSetViolation(
        'DUP_IN_SET',
        '$setName contains duplicate digests {${sorted.join(", ")}}',
      );
    }
  }

  static void _assertNoOverlap(
    String nameA,
    List<String> a,
    String nameB,
    List<String> b,
  ) {
    final setB = b.toSet();
    final shared = a.where(setB.contains).toSet();
    if (shared.isNotEmpty) {
      final sorted = shared.toList()..sort();
      throw ProbeSetViolation(
        'PROBE_OVERLAP',
        '$nameA∩$nameB={${sorted.join(", ")}}',
      );
    }
  }
}
