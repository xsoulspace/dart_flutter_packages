import 'hlc.dart';
import 'lww_map_strategy.dart';
import 'op_record.dart';

/// Sequence merge strategy (RGA family) for block text — the kernel
/// obligation pulled forward by ADR 0029: streamed agent text must merge
/// causally once a second peer connects.
///
/// One keyed multi-root RGA per text key (e.g. one key per document
/// block). Elements are individual characters with deterministic ids
/// derived from the issuing op (`'<opId>#<index>'`), chained after a
/// referenced element (or the root). Order is resolved by tree traversal:
/// children of each anchor sort by `(Hlc, indexInOp)`, a total order —
/// so fold is commutative, idempotent, and independent of delivery order.
///
/// Op payloads:
/// - insert: `{'k': key, 'after': <elementId|null>, 'text': String}`
///   (each character becomes one element; element *i* of the op sits
///   after element *i-1*, the first after [after]).
/// - delete: `{'k': key, 'del': [elementId, ...]}` (tombstones; may
///   arrive before the referenced elements — tombstones win whenever the
///   element appears).
final class RgaTextStrategy implements MergeStrategy {
  const RgaTextStrategy();

  @override
  String get name => 'rga_text';

  @override
  Map<String, Object?> initialState() => <String, Object?>{};

  @override
  void fold(final Map<String, Object?> state, final OpRecord op) {
    final key = op.payload['k'];
    if (key is! String || key.isEmpty) {
      throw ArgumentError.value(
        op.payload,
        'op.payload',
        'RgaTextStrategy requires a non-empty string "k"',
      );
    }
    final tombstones = op.payload['del'];
    if (tombstones != null) {
      _foldDelete(state, key, tombstones);
      return;
    }
    _foldInsert(state, key, op);
  }

  void _foldInsert(
    final Map<String, Object?> state,
    final String key,
    final OpRecord op,
  ) {
    final text = op.payload['text'];
    if (text is! String || text.isEmpty) {
      throw ArgumentError.value(
        op.payload,
        'op.payload',
        'RgaTextStrategy insert requires a non-empty string "text"',
      );
    }
    final after = op.payload['after'];
    if (after != null && after is! String) {
      throw ArgumentError.value(
        op.payload,
        'op.payload',
        'RgaTextStrategy "after" must be null or an element id',
      );
    }
    final bucket = _bucket(state, key);
    final nodes = bucket['nodes']! as Map<String, Object?>;
    var anchor = after as String?;
    for (var i = 0; i < text.length; i++) {
      final id = '${op.opId}#$i';
      if (!nodes.containsKey(id)) {
        nodes[id] = {'a': anchor, 'c': text[i], 'h': op.hlc.toJson(), 'i': i};
      }
      // The chain continues even on redelivery: later elements of the
      // same op anchor on their predecessors' ids regardless.
      anchor = id;
    }
  }

  void _foldDelete(
    final Map<String, Object?> state,
    final String key,
    final Object? tombstones,
  ) {
    if (tombstones is! List || tombstones.isEmpty) {
      throw ArgumentError.value(
        tombstones,
        'op.payload["del"]',
        'RgaTextStrategy delete requires a non-empty element id list',
      );
    }
    final bucket = _bucket(state, key);
    final tomb = bucket['tomb']! as Map<String, Object?>;
    for (final id in tombstones) {
      if (id is! String || id.isEmpty) {
        throw ArgumentError.value(
          tombstones,
          'op.payload["del"]',
          'RgaTextStrategy tombstones must be non-empty element ids',
        );
      }
      tomb[id] = true;
    }
  }

  /// Per-key storage: `{'nodes': {id: node}, 'tomb': {id: true}}`. All
  /// JSON-encodable; tombstones recorded before their element arrives are
  /// honored at read time.
  static Map<String, Object?> _bucket(
    final Map<String, Object?> state,
    final String key,
  ) {
    final existing = state[key];
    if (existing is Map<String, Object?>) return existing;
    if (existing != null) {
      throw StateError('RgaTextStrategy key "$key" holds foreign state');
    }
    final bucket = <String, Object?>{
      'nodes': <String, Object?>{},
      'tomb': <String, Object?>{},
    };
    state[key] = bucket;
    return bucket;
  }

  /// Materialized visible text for [key]; `null` when the key is absent.
  ///
  /// Deterministic tree traversal: root children, then depth-first, each
  /// sibling list ordered by `(Hlc, indexInOp)`. Unresolvable elements
  /// (anchor not yet received) are simply not visited — they appear when
  /// their anchor arrives, deterministically on every replica.
  static String? readText(final Map<String, Object?> state, final String key) {
    final raw = state[key];
    if (raw is! Map<String, Object?>) return null;
    final nodesRaw = raw['nodes'];
    final tombRaw = raw['tomb'];
    if (nodesRaw is! Map) return null;
    final nodes = <String, Map<String, Object?>>{
      for (final entry in nodesRaw.entries)
        entry.key as String: Map<String, Object?>.from(
          entry.value as Map<dynamic, dynamic>,
        ),
    };
    final tomb = <String, bool>{
      if (tombRaw is Map)
        for (final entry in tombRaw.entries)
          entry.key as String: entry.value == true,
    };

    // Index children by anchor.
    final children = <String?, List<MapEntry<String, Map<String, Object?>>>>{};
    nodes.forEach((final id, final node) {
      final anchor = node['a'] as String?;
      children.putIfAbsent(anchor, () => []).add(MapEntry(id, node));
    });
    // Total order within each sibling list.
    for (final list in children.values) {
      list.sort((final a, final b) {
        final ha = hlcFromJson(a.value['h']);
        final hb = hlcFromJson(b.value['h']);
        final byHlc = ha.compareTo(hb);
        if (byHlc != 0) return byHlc;
        return (a.value['i']! as int).compareTo(b.value['i']! as int);
      });
    }

    final buffer = StringBuffer();
    void visit(final String? anchor) {
      final siblings =
          children[anchor] ?? const <MapEntry<String, Map<String, Object?>>>[];
      for (final entry in siblings) {
        if (!(tomb[entry.key] ?? false)) buffer.write(entry.value['c']);
        visit(entry.key);
      }
    }

    visit(null);
    return buffer.toString();
  }

  /// Element ids currently live (non-tombstoned) for [key] — the anchors
  /// a local editor needs to issue the next insert.
  static Set<String> liveElementIds(
    final Map<String, Object?> state,
    final String key,
  ) {
    final raw = state[key];
    if (raw is! Map<String, Object?>) return const {};
    final nodesRaw = raw['nodes'];
    final tombRaw = raw['tomb'];
    if (nodesRaw is! Map) return const {};
    final tomb = <String, bool>{
      if (tombRaw is Map)
        for (final entry in tombRaw.entries) entry.key as String: true,
    };
    return {
      for (final id in nodesRaw.keys.whereType<String>())
        if (!tomb[id]!) id,
    };
  }
}
