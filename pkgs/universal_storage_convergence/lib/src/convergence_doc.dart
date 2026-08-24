import 'package:meta/meta.dart';

import 'hlc.dart';
import 'lww_map_strategy.dart';
import 'op_record.dart';
import 'version_vector.dart';

/// Snapshot of a document's folded state at a version-vector watermark
/// (ADR 0011 §1). Derived data: never the source of truth while ops for it
/// still exist on any replica.
@immutable
final class Snapshot {
  const Snapshot({
    required this.docId,
    required this.baseVv,
    required this.state,
    required this.createdAt,
  });

  factory Snapshot.fromJson(final Map<String, dynamic> json) => Snapshot(
    docId: json['doc_id'] as String,
    baseVv: VersionVector.fromJson(
      Map<String, dynamic>.from(json['base_vv'] as Map<dynamic, dynamic>),
    ),
    state: Map<String, Object?>.from(json['state'] as Map<dynamic, dynamic>),
    createdAt: hlcFromJson(json['created_at']),
  );

  final String docId;
  final VersionVector baseVv;
  final Map<String, Object?> state;
  final Hlc createdAt;

  Map<String, dynamic> toJson() => {
    'doc_id': docId,
    'base_vv': baseVv.toJson(),
    'state': state,
    'created_at': createdAt.toJson(),
  };
}

/// Dual-mode convergence document: an incrementally-folded [state] plus a
/// pending op [log] used to ship deltas to lagging replicas
/// (ADR 0011 §1).
///
/// Invariants:
/// - `state` is always the fold of snapshot ∪ every applied op.
/// - Ops are folded in ascending [Hlc] order, so arrival order never
///   affects the result.
/// - [VersionVector] dedupe makes remote application idempotent.
final class ConvergenceDoc {
  ConvergenceDoc({
    required this.docId,
    required this.actorId,
    this.strategy = const LwwMapStrategy(),
  }) : _state = strategy.initialState();

  ConvergenceDoc._(
    this.docId,
    this.actorId,
    this.strategy,
    this._state,
    this._vv,
    this._log,
  );

  final String docId;
  final String actorId;

  /// Merge semantics for payloads. Fixed per document instance; changing a
  /// doc's strategy across replicas is a protocol-breaking change.
  final MergeStrategy strategy;

  Map<String, Object?> _state;
  VersionVector _vv = VersionVector.zero;
  List<OpRecord> _log = [];

  /// Read-only view of the current folded state.
  Map<String, Object?> get state => Map.unmodifiable(_state);

  /// High-water marks of applied ops per actor.
  VersionVector get vv => _vv;

  /// Ops retained for delta shipping (not yet compacted).
  List<OpRecord> get pendingOps => List.unmodifiable(_log);

  /// Creates a local op from [payload], folds it immediately, and returns
  /// it for durable append by the caller.
  OpRecord applyLocal(
    final Map<String, Object?> payload,
    final DateTime now, {
    Hlc? lastIssued,
  }) {
    final previous = _vv[actorId] ?? Hlc.zero(actorId);
    final hlc = previous.tick(now);
    final op = OpRecord(docId: docId, hlc: hlc, payload: payload);
    strategy.fold(_state, op);
    _vv = _vv.observed(hlc);
    _log = [..._log, op];
    return op;
  }

  /// Folds [ops] from remote replicas. Dedupes via the version vector and
  /// folds in ascending HLC order. Returns how many ops were new.
  int applyRemote(final Iterable<OpRecord> ops) {
    final fresh =
        ops.where((final op) => op.docId == docId && !_vv.contains(op.hlc))
            .toList()
          ..sort((final a, final b) => a.hlc.compareTo(b.hlc));
    for (final op in fresh) {
      strategy.fold(_state, op);
      _vv = _vv.observed(op.hlc);
    }
    if (fresh.isNotEmpty) {
      _log = [..._log, ...fresh]..sort(
        (final a, final b) => a.hlc.compareTo(b.hlc),
      );
    }
    return fresh.length;
  }

  /// Ops this replica holds that [remoteVv] has not observed.
  List<OpRecord> opsSince(final VersionVector remoteVv) =>
      _log.where((final op) => !remoteVv.contains(op.hlc)).toList();

  /// True when [remoteVv] is fully covered but the peer still needs content
  /// (our log was compacted) — caller should ship a [snapshotFor] instead.
  bool needsSnapshotFor(final VersionVector remoteVv) =>
      opsSince(remoteVv).isEmpty && !_coveredBy(remoteVv);

  bool _coveredBy(final VersionVector remoteVv) {
    for (final actor in _vv.actors) {
      final ours = _vv[actor]!;
      final theirs = remoteVv[actor];
      if (theirs == null || theirs < ours) return false;
    }
    return true;
  }

  /// Current state as a snapshot at our own watermark.
  Snapshot snapshotFor() => Snapshot(
    docId: docId,
    baseVv: _vv,
    state: Map.of(_state),
    createdAt: _vv[actorId] ?? Hlc.zero(actorId),
  );

  /// Adopts [snapshot] only when it carries events we have not seen.
  /// Returns true when adopted.
  bool adoptSnapshot(final Snapshot snapshot) {
    if (snapshot.docId != docId) return false;
    var newer = false;
    for (final actor in snapshot.baseVv.actors) {
      final theirs = snapshot.baseVv[actor]!;
      final ours = _vv[actor];
      if (ours == null || theirs > ours) newer = true;
    }
    if (!newer) return false;
    // Adopt wholesale: snapshot state is authoritative for everything up to
    // its base vector. Local pending ops beyond it are re-applied.
    final localPending = _log
        .where((final op) => !snapshot.baseVv.contains(op.hlc))
        .toList()
      ..sort((final a, final b) => a.hlc.compareTo(b.hlc));
    _state = strategy.initialState();
    // Seed fold with snapshot entries as pseudo-wins by merging vectors:
    // fold each snapshot key through the strategy so entry metadata survives.
    snapshot.state.forEach((final key, final value) {
      _state[key] = value;
    });
    _vv = snapshot.baseVv;
    _log = localPending;
    for (final op in localPending) {
      strategy.fold(_state, op);
      _vv = _vv.observed(op.hlc);
    }
    return true;
  }

  /// Dual-mode compaction: the current state acts as the snapshot; the
  /// pending log is truncated. Callers must ensure lagging peers can catch
  /// up via snapshots afterwards ([needsSnapshotFor]).
  ///
  /// Returns the number of retired ops.
  int compact() {
    final retired = _log.length;
    _log = [];
    return retired;
  }

  /// Full serialization for durable local persistence.
  Map<String, dynamic> toJson() => {
    'doc_id': docId,
    'actor_id': actorId,
    'strategy': 'lww_map',
    'state': _state,
    'vv': _vv.toJson(),
    'log': _log.map((final op) => op.toJson()).toList(),
  };

  factory ConvergenceDoc.fromJson(final Map<String, dynamic> json) {
    final strategyName = json['strategy'] as String? ?? 'lww_map';
    if (strategyName != 'lww_map') {
      throw ArgumentError.value(strategyName, 'strategy', 'Unknown strategy');
    }
    final doc = ConvergenceDoc._(
      json['doc_id'] as String,
      json['actor_id'] as String,
      const LwwMapStrategy(),
      Map<String, Object?>.from(json['state'] as Map<dynamic, dynamic>),
      VersionVector.fromJson(
        Map<String, dynamic>.from(json['vv'] as Map<dynamic, dynamic>),
      ),
      (json['log'] as List<dynamic>? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map(OpRecord.fromJson)
          .toList(),
    );
    return doc;
  }
}
