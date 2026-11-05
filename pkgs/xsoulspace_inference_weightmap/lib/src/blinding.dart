/// Seeded arm blinding with verdict-frozen unblinding.
///
/// Implements PROGRAM.md §3 (Blinding): arm labels are shuffled by a seeded
/// script, the seed is frozen in PREREG-A (20261105) so it cannot be
/// re-picked post hoc, the certifier sees arm IDs only, and unblinding
/// happens ONLY after the verdict file is frozen. Ported from `~/xs/pattern`'s
/// propose-only discipline: the key never influences a verdict — it is
/// released against an existing frozen verdict artifact or not at all, so
/// label peeking before freeze is structurally impossible, not merely rude.
///
/// Refusals are NAMED results ([UnblindRefused]), never exceptions and never
/// a silent empty map: VERDICT_NOT_FROZEN, KEY_FILE_MISSING,
/// KEY_FILE_MALFORMED, KEY_FILE_TAMPERED.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'ledger.dart' show canonicalJson;

/// A deterministic blinding of [arms] under a frozen [seed]: each real arm id
/// maps to an opaque `arm-NNN` label, assigned by shuffling the label list
/// with `math.Random(seed)`.
///
/// Determinism contract: the same (seed, arms) produce the same map on every
/// instance and every run on a given Dart SDK (the SDK's [math.Random]
/// sequence is seed-determined; [List.shuffle] is Fisher-Yates over it).
final class BlindingPlan {
  factory BlindingPlan.fromSeed(int seed, List<String> arms) {
    if (arms.isEmpty) {
      throw ArgumentError.value(arms, 'arms', 'EMPTY_ARMS');
    }
    final seen = <String>{};
    for (final arm in arms) {
      if (!seen.add(arm)) {
        throw ArgumentError.value(arms, 'arms', 'DUPLICATE_ARMS=$arm');
      }
    }
    final labels = [
      for (var i = 0; i < arms.length; i++)
        'arm-${i.toString().padLeft(3, '0')}',
    ]..shuffle(math.Random(seed));
    final armToLabel = Map<String, String>.unmodifiable({
      for (var i = 0; i < arms.length; i++) arms[i]: labels[i],
    });
    final labelToArm = Map<String, String>.unmodifiable({
      for (final e in armToLabel.entries) e.value: e.key,
    });
    return BlindingPlan._(
      seed,
      List<String>.unmodifiable(arms),
      armToLabel,
      labelToArm,
    );
  }

  const BlindingPlan._(this.seed, this.arms, this.armToLabel, this.labelToArm);

  /// The frozen seed (PREREG-A law: frozen pre-result, never re-picked).
  final int seed;

  /// The real arm ids, in registration order.
  final List<String> arms;

  /// Real arm id -> opaque label. What the certifier must NOT see pre-freeze.
  final Map<String, String> armToLabel;

  /// Opaque label -> real arm id. The analysis direction, post-freeze.
  final Map<String, String> labelToArm;

  /// Writes the unblinding key as canonical json (byte-stable, digestable).
  /// The key file is the operational artifact; access discipline lives in the
  /// harness, and [unblind] enforces the verdict-frozen gate mechanically.
  void writeKeyFile(File path) {
    final encoded = canonicalJson({
      'seed': seed,
      'arms': arms,
      'armToLabel': armToLabel,
    });
    path.parent.createSync(recursive: true);
    path.writeAsStringSync('$encoded\n', flush: true);
  }

  /// Reads and VERIFIES a key file: the stored map must equal the map
  /// re-derived from the stored (seed, arms), so a hand-edited key is a named
  /// failure (ArgumentError KEY_FILE_TAMPERED), not a trusted input.
  /// Malformed json/fields throw named [FormatException]s (KEY_FILE_MALFORMED).
  static BlindingPlan readKeyFile(File path) {
    final Object? decoded;
    try {
      decoded = jsonDecode(path.readAsStringSync());
    } on FormatException catch (e) {
      throw FormatException('KEY_FILE_MALFORMED invalid json: ${e.message}');
    }
    if (decoded is! Map) {
      throw const FormatException('KEY_FILE_MALFORMED root is not an object');
    }
    final seed = decoded['seed'];
    if (seed is! int) {
      throw FormatException(
        'KEY_FILE_MALFORMED seed expected=int found=${seed.runtimeType}',
      );
    }
    final arms = decoded['arms'];
    if (arms is! List || arms.any((a) => a is! String)) {
      throw const FormatException('KEY_FILE_MALFORMED arms');
    }
    final stored = decoded['armToLabel'];
    if (stored is! Map) {
      throw const FormatException('KEY_FILE_MALFORMED armToLabel');
    }
    final plan = BlindingPlan.fromSeed(seed, arms.cast<String>());
    if (canonicalJson(plan.armToLabel) != canonicalJson(stored)) {
      throw ArgumentError(
        'KEY_FILE_TAMPERED stored armToLabel != re-derivation from seed=$seed '
        '(the key file is verified, not trusted)',
      );
    }
    return plan;
  }
}

/// Result union of [unblind]: the released map, or a named refusal.
sealed class UnblindResult {
  const UnblindResult();
}

/// The released arm id -> label map (unmodifiable), after the verdict froze.
final class Unblinded extends UnblindResult {
  const Unblinded(this.armToLabel);

  final Map<String, String> armToLabel;
}

/// A named refusal. [reason] is the frozen vocabulary: VERDICT_NOT_FROZEN,
/// KEY_FILE_MISSING, KEY_FILE_MALFORMED, KEY_FILE_TAMPERED.
final class UnblindRefused extends UnblindResult {
  const UnblindRefused({required this.reason, this.detail = ''});

  final String reason;
  final String detail;

  @override
  String toString() =>
      'UNBLIND_REFUSED reason=$reason${detail.isEmpty ? '' : ' $detail'}';
}

/// Releases the arm id -> label map ONLY if [verdictFrozen] exists.
///
/// The verdict gate is checked FIRST — before the key file is even looked
/// for — so "no frozen verdict" is refused identically whether or not a key
/// is present (PROGRAM.md §3: unblind only after the verdict file is frozen).
/// A missing, malformed, or tampered key is likewise a named refusal; this
/// function never throws for those states and never returns a partial map.
UnblindResult unblind(File keyFile, {required File verdictFrozen}) {
  if (!verdictFrozen.existsSync()) {
    return UnblindRefused(
      reason: 'VERDICT_NOT_FROZEN',
      detail: 'verdict file ${verdictFrozen.path} does not exist; labels are '
          'released only against a frozen verdict',
    );
  }
  if (!keyFile.existsSync()) {
    return UnblindRefused(
      reason: 'KEY_FILE_MISSING',
      detail: keyFile.path,
    );
  }
  try {
    return Unblinded(BlindingPlan.readKeyFile(keyFile).armToLabel);
  } on FormatException catch (e) {
    return UnblindRefused(reason: 'KEY_FILE_MALFORMED', detail: e.message);
  } on ArgumentError catch (e) {
    return UnblindRefused(
      reason: 'KEY_FILE_TAMPERED',
      detail: '${e.message}',
    );
  }
}
