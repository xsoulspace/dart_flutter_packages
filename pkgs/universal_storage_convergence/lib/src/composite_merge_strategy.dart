import 'convergence_doc.dart';
import 'lww_map_strategy.dart';
import 'op_record.dart';

/// Named error thrown when an op's payload key matches no lane of a
/// [CompositeMergeStrategy] (ADR 0030 §1). The composite refuses the op
/// loudly instead of silently dropping it — redelivery attempts the fold
/// again, so the op is never lost without a named diagnostic.
final class CompositeLaneMismatchError extends Error {
  CompositeLaneMismatchError(this.key, this.lanePrefixes);

  /// The offending payload key (`null` when the op carries no key at all).
  final Object? key;
  final Iterable<String> lanePrefixes;

  @override
  String toString() =>
      'CompositeLaneMismatchError: op key "$key" matches no lane prefix '
      '[${lanePrefixes.join(', ')}] — refusing the op, never dropping it '
      '(ADR 0030 §1)';
}

/// Composes several fold semantics into one strategy via key-prefix
/// dispatch (ADR 0030 §1): the strategy is constructed from an **ordered
/// lane map** (`key prefix → sub-strategy`) and folds each op through the
/// lane whose prefix longest-matches the op's payload key.
///
/// Contract:
/// - Every op MUST match exactly one lane (the longest matching prefix).
///   An op matching no lane raises [CompositeLaneMismatchError] — named,
///   never silently dropped.
/// - Lanes must be key-addressed flat-map strategies (both shipped ones —
///   `LwwMapStrategy`, `RgaTextStrategy` — are): the composite keeps ONE
///   shared state map, and disjoint lane prefixes guarantee lanes never
///   touch each other's keys. That disjointness is what makes
///   commutativity/idempotence **inherited**: when every lane is
///   commutative and idempotent, the composite is too, for any delivery
///   order, lane interleaving, and batch split.
/// - One `ConvergenceDoc` per document: ONE version vector, ONE op log,
///   ONE snapshot/compaction decision, ONE anti-entropy header — the
///   composite adds no merge semantics of its own.
/// - The lane map is part of the registry name: `composite:<lane-spec-id>`
///   (e.g. `composite:node/=>lww_map,order/=>lww_map,text/=>rga_text`),
///   wire-stable and restorable through `ConvergenceDoc.fromJson` without
///   parent-side re-routing. A spec naming an unknown sub-strategy is a
///   named error on restore.
final class CompositeMergeStrategy implements MergeStrategy {
  /// Validates and wraps [lanes] (insertion order = lane order).
  factory CompositeMergeStrategy(final Map<String, MergeStrategy> lanes) {
    if (lanes.isEmpty) {
      throw ArgumentError.value(lanes, 'lanes', 'must have at least one lane');
    }
    for (final prefix in lanes.keys) {
      if (prefix.isEmpty) {
        throw ArgumentError.value(prefix, 'lanes keys', 'empty lane prefix');
      }
      if (prefix.contains(',') || prefix.contains('>')) {
        throw ArgumentError.value(
          prefix,
          'lanes keys',
          'lane prefix must not contain "," or ">" (spec encoding)',
        );
      }
    }    return CompositeMergeStrategy._(Map.unmodifiable(lanes));
  }

  /// Restores a composite from its wire spec (the part after
  /// `composite:` in [CompositeMergeStrategy.name]). Unknown
  /// sub-strategy names are a named error — a lane-map mismatch on
  /// restore is never a silent re-route (ADR 0030 §1).
  factory CompositeMergeStrategy.fromSpec(final String spec) {
    if (spec.isEmpty) {
      throw ArgumentError.value(spec, 'spec', 'empty lane spec');
    }
    final lanes = <String, MergeStrategy>{};
    for (final part in spec.split(',')) {
      final separator = part.indexOf('=>');
      if (separator <= 0 || separator == part.length - 2) {
        throw ArgumentError.value(
          part,
          'spec',
          'malformed lane (expected "prefix=>strategy")',
        );
      }
      final prefix = part.substring(0, separator);
      final strategyName = part.substring(separator + 2);
      lanes[prefix] = ConvergenceDoc.strategyFor(strategyName);
    }
    return CompositeMergeStrategy(lanes);
  }

  const CompositeMergeStrategy._(this.lanes);

  /// Ordered lane map: key prefix → sub-strategy. Longest matching prefix
  /// wins; prefixes are distinct and spec-encodable (validated in the
  /// factory).
  final Map<String, MergeStrategy> lanes;

  /// Registry-name prefix shared by every composite strategy (ADR 0030 §1).
  static const String specPrefix = 'composite:';

  /// Registry name (serialization contract of `ConvergenceDoc.fromJson`).
  @override
  String get name {
    final laneSpec = lanes.entries
        .map((final e) => '${e.key}=>${e.value.name}')
        .join(',');
    return '$specPrefix$laneSpec';
  }

  @override
  Map<String, Object?> initialState() => <String, Object?>{};

  @override
  void fold(final Map<String, Object?> state, final OpRecord op) =>
      laneFor(op).fold(state, op);

  /// The lane owning [op]: longest-matching prefix over its payload key.
  /// Throws [CompositeLaneMismatchError] when no lane matches (or the op
  /// carries no string key) — named, never dropped.
  MergeStrategy laneFor(final OpRecord op) {
    final key = op.payload['k'];
    String? best;
    var bestLength = -1;
    if (key is String) {
      for (final prefix in lanes.keys) {
        if (prefix.length > bestLength && key.startsWith(prefix)) {
          best = prefix;
          bestLength = prefix.length;
        }
      }
    }
    if (best == null) {
      throw CompositeLaneMismatchError(key, lanes.keys.toList(growable: false));
    }
    return lanes[best]!;
  }
}
