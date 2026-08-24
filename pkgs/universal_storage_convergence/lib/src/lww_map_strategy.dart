import 'hlc.dart';
import 'op_record.dart';

/// Fold semantics for one document type (ADR 0011 §2).
///
/// Strategies MUST be commutative and idempotent over op sets: applying the
/// same ops in any order (any number of times) yields identical state. The
/// kernel enforces deterministic arrival by sorting on [Hlc] before folding,
/// but strategies must not rely on that alone.
abstract interface class MergeStrategy {
  /// Fresh, empty state container for a document.
  Map<String, Object?> initialState();

  /// Folds [op] into [state] in place.
  void fold(Map<String, Object?> state, OpRecord op);
}

/// Last-writer-wins map strategy: keys are independent LWW registers
/// ordered by [Hlc]. Sufficient for settings, saves metadata, and
/// structured JSON namespaces (ADR 0011 §2).
///
/// Op payloads:
/// - set: `{'k': key, 'v': value}`
/// - delete: `{'k': key, 'del': true}` (tombstone; keeps winning so deletes
///   propagate to replicas that never saw the value).
final class LwwMapStrategy implements MergeStrategy {
  const LwwMapStrategy();

  static const _deletedKey = 'del';

  @override
  Map<String, Object?> initialState() => <String, Object?>{};

  @override
  void fold(final Map<String, Object?> state, final OpRecord op) {
    final key = op.payload['k'];
    if (key is! String || key.isEmpty) {
      throw ArgumentError.value(
        op.payload,
        'op.payload',
        'LwwMapStrategy requires a non-empty string "k"',
      );
    }
    final existing = _readEntry(state[key]);
    if (existing != null && existing.$1 >= op.hlc) return;

    final deleted = op.payload[_deletedKey] == true;
    final value = deleted ? null : op.payload['v'];
    state[key] = {
      'v': value,
      _deletedKey: deleted,
      'hlc': op.hlc.toJson(),
    };
  }

  /// Reads the current value for [key]; returns `null` when missing or
  /// tombstoned.
  static String? readValue(final Map<String, Object?> state, final String key) {
    final entry = _readEntry(state[key]);
    if (entry == null || entry.$2) return null;
    return entry.$3 as String?;
  }

  /// Reads the HLC that last wrote [key]; `null` when the key is absent.
  static Hlc? readHlc(final Map<String, Object?> state, final String key) {
    final entry = _readEntry(state[key]);
    return entry?.$1;
  }

  static (Hlc, bool, Object?)? _readEntry(final Object? raw) {
    if (raw is! Map) return null;
    final hlcRaw = raw['hlc'];
    if (hlcRaw is! Map) return null;
    return (
      hlcFromJson(Map<String, dynamic>.from(hlcRaw)),
      raw[_deletedKey] == true,
      raw['v'],
    );
  }
}
