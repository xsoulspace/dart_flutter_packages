import 'package:meta/meta.dart';

import 'composite_merge_strategy.dart';
import 'hlc.dart';
import 'lww_map_strategy.dart';
import 'op_record.dart';
import 'rga_text_strategy.dart';
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
  }) : _state = strategy.initialState(),
       _ephemeralState = strategy.initialState();

  factory ConvergenceDoc.fromJson(final Map<String, dynamic> json) {
    final doc = ConvergenceDoc._(
      json['doc_id'] as String,
      json['actor_id'] as String,
      strategyFor(json['strategy'] as String? ?? 'lww_map'),
      Map<String, Object?>.from(json['state'] as Map<dynamic, dynamic>),
      VersionVector.fromJson(
        Map<String, dynamic>.from(json['vv'] as Map<dynamic, dynamic>),
      ),
      (json['log'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map((final e) => OpRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
    doc._seenOpIds.addAll(
      (json['seen_op_ids'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>(),
    );
    // Ephemeral state/log (ADR 0029 §1): restored as-is; expired entries
    // are dropped by the next [sweepEphemeral] or expiry-checked
    // applyRemote. Monotonicity guard spans both logs.
    doc._ephemeralLog =
        (json['ephemeral_log'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map((final e) => OpRecord.fromJson(Map<String, dynamic>.from(e)))
            .toList();
    doc._ephemeralState = Map<String, Object?>.from(
      json['ephemeral_state'] as Map<dynamic, dynamic>? ?? const {},
    );
    for (final op in doc._log) {
      doc._seenOpIds.add(op.opId);
      if (op.actorId == doc.actorId) doc._observeIssued(op.hlc);
    }
    for (final op in doc._ephemeralLog) {
      doc._seenOpIds.add(op.opId);
      if (op.actorId == doc.actorId) doc._observeIssued(op.hlc);
    }
    return doc;
  }

  ConvergenceDoc._(
    this.docId,
    this.actorId,
    this.strategy,
    this._state,
    this._vv,
    this._log,
  ) : _ephemeralState = strategy.initialState();

  /// Strategy registry (serialization contract). Changing a doc's
  /// strategy across replicas is a protocol-breaking change (ADR 0011).
  /// Composite strategies restore their full lane map from the wire-stable
  /// `composite:<lane-spec-id>` name — no parent-side re-routing (ADR 0030 §1).
  static MergeStrategy strategyFor(final String name) {
    if (name == 'lww_map') return const LwwMapStrategy();
    if (name == 'rga_text') return const RgaTextStrategy();
    if (name.startsWith(CompositeMergeStrategy.specPrefix)) {
      return CompositeMergeStrategy.fromSpec(
        name.substring(CompositeMergeStrategy.specPrefix.length),
      );
    }
    throw ArgumentError.value(name, 'name', 'Unknown strategy');
  }

  final String docId;
  final String actorId;

  /// Merge semantics for payloads. Fixed per document instance; changing a
  /// doc's strategy across replicas is a protocol-breaking change.
  final MergeStrategy strategy;

  Map<String, Object?> _state;
  VersionVector _vv = VersionVector.zero;
  List<OpRecord> _log = [];

  /// Ephemeral fold (ADR 0029 §1): the agent-queryable live registry —
  /// a fold over unexpired ephemeral ops. Never part of [state],
  /// snapshots, or the durable version vector.
  Map<String, Object?> _ephemeralState;

  /// Ephemeral ops retained for delta shipping until they expire.
  List<OpRecord> _ephemeralLog = [];

  /// Highest HLC this replica has ISSUED (durable or ephemeral). Ephemeral
  /// ops do not advance the durable version vector, so without this guard
  /// a durable op issued right after an ephemeral one would reuse the same
  /// HLC — and collide in `_seenOpIds` (silent drop).
  Hlc? _lastIssued;

  /// Exact dedupe set. Version-vector checks assume per-actor ordering,
  /// which delivery does NOT guarantee — arbitrary-order arrival is part of
  /// the kernel contract (see `test/convergence_property_test.dart`).
  /// Re-folding an already-folded op is harmless under LWW, so this set
  /// exists to keep logs and counters honest, not for safety.
  final Set<String> _seenOpIds = {};

  /// Read-only view of the current folded state.
  Map<String, Object?> get state => Map.unmodifiable(_state);

  /// Read-only fold over unexpired ephemeral ops (ADR 0029 §1) — the
  /// agent-queryable presence/live registry. Callers owning a clock should
  /// [sweepEphemeral] before reading.
  Map<String, Object?> get ephemeralState => Map.unmodifiable(_ephemeralState);

  /// Ephemeral ops retained for delta shipping (not yet expired). Dedupe
  /// on delivery is by [OpRecord.opId] — ephemeral ops intentionally do
  /// not advance the durable version vector, so `opsSince` VV logic does
  /// not apply to them.
  List<OpRecord> get pendingEphemeralOps => List.unmodifiable(_ephemeralLog);

  /// Drops expired ephemeral ops from the fold and the delta log; returns
  /// how many were dropped. Expiry is commutative and idempotent: any
  /// replica applying the same (expired) op set converges identically.
  int sweepEphemeral(final DateTime now) {
    final live =
        _ephemeralLog.where((final op) => !op.isExpiredAt(now)).toList()
          ..sort((final a, final b) => a.hlc.compareTo(b.hlc));
    final dropped = _ephemeralLog.length - live.length;
    if (dropped == 0) return 0;
    _ephemeralState = strategy.initialState();
    for (final op in live) {
      strategy.fold(_ephemeralState, op);
    }
    _ephemeralLog = live;
    return dropped;
  }

  void _observeIssued(final Hlc hlc) {
    final current = _lastIssued;
    if (current == null || hlc > current) _lastIssued = hlc;
  }

  static Hlc? _maxIssued(final Iterable<Hlc?> candidates) {
    Hlc? max;
    for (final candidate in candidates) {
      if (candidate != null && (max == null || candidate > max)) {
        max = candidate;
      }
    }
    return max;
  }

  /// High-water marks of applied ops per actor.
  VersionVector get vv => _vv;

  /// Ops retained for delta shipping (not yet compacted).
  List<OpRecord> get pendingOps => List.unmodifiable(_log);

  /// Creates a local op from [payload], folds it immediately, and returns
  /// it for durable append by the caller. [lastIssued] (a restored
  /// watermark) participates in the monotonicity guard.
  OpRecord applyLocal(
    final Map<String, Object?> payload,
    final DateTime now, {
    Hlc? lastIssued,
  }) {
    final previous =
        _maxIssued([_vv[actorId], lastIssued, _lastIssued]) ??
        Hlc.zero(actorId);
    final hlc = previous.tick(now);
    _observeIssued(hlc);
    final op = OpRecord(docId: docId, hlc: hlc, payload: payload);
    strategy.fold(_state, op);
    _vv = _vv.observed(hlc);
    _log = [..._log, op];
    _seenOpIds.add(op.opId);
    return op;
  }

  /// Creates a local EPHEMERAL op (ADR 0029 §1): folds into
  /// [ephemeralState], never into durable state or the durable version
  /// vector. Rides the same dedupe and ordering as durable ops.
  OpRecord applyLocalEphemeral(
    final Map<String, Object?> payload,
    final DateTime now, {
    required final Duration ttl,
  }) {
    final previous =
        _maxIssued([_vv[actorId], _lastIssued]) ?? Hlc.zero(actorId);
    final hlc = previous.tick(now);
    _observeIssued(hlc);
    final op = OpRecord(docId: docId, hlc: hlc, payload: payload, ttl: ttl);
    strategy.fold(_ephemeralState, op);
    _ephemeralLog = [..._ephemeralLog, op];
    _seenOpIds.add(op.opId);
    return op;
  }

  /// Folds [ops] from remote replicas. Dedupes via the exact op-id set and
  /// folds in ascending HLC order. Durable ops advance the version vector;
  /// ephemeral ops fold into [ephemeralState] and are DROPPED when expired
  /// relative to [now] (expired ops stay deduped — expiry is monotonic in
  /// real time). Returns how many ops were newly applied.
  int applyRemote(final Iterable<OpRecord> ops, {final DateTime? now}) {
    // Dedupe WITHOUT committing yet: an op is marked seen only after its
    // fold succeeded (or it was deliberately dropped as expired), so a
    // fold error — e.g. a composite lane mismatch (ADR 0030 §1) — leaves
    // the op unseen and redelivery retries it. Ops are never silently
    // dropped on a failed fold.
    final freshById = <String, OpRecord>{};
    for (final op in ops) {
      if (op.docId != docId || _seenOpIds.contains(op.opId)) continue;
      freshById.putIfAbsent(op.opId, () => op);
    }
    final fresh = freshById.values.toList()
      ..sort((final a, final b) => a.hlc.compareTo(b.hlc));
    var applied = 0;
    final durable = <OpRecord>[];
    for (final op in fresh) {
      if (op.ttl != null) {
        // Expired ops stay deduped — expiry is monotonic in real time.
        if (now != null && op.isExpiredAt(now)) {
          _seenOpIds.add(op.opId);
          continue;
        }
        strategy.fold(_ephemeralState, op);
        _seenOpIds.add(op.opId);
        _ephemeralLog = [..._ephemeralLog, op];
        applied++;
      } else {
        durable.add(op);
      }
    }
    for (final op in durable) {
      strategy.fold(_state, op);
      _vv = _vv.observed(op.hlc);
      _seenOpIds.add(op.opId);
    }
    if (durable.isNotEmpty) {
      applied += durable.length;
      _log = [..._log, ...durable]
        ..sort((final a, final b) => a.hlc.compareTo(b.hlc));
    }
    return applied;
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
    final localPending =
        _log.where((final op) => !snapshot.baseVv.contains(op.hlc)).toList()
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
    // Post-compaction, lagging peers are served snapshots; stale dedupe
    // entries only bound memory — re-folding a duplicate is safe. Ephemeral
    // ids are kept so redelivered ephemeral ops are not re-folded past
    // their expiry check.
    _seenOpIds.clear();
    for (final op in _ephemeralLog) {
      _seenOpIds.add(op.opId);
    }
    return retired;
  }

  /// Full serialization for durable local persistence.
  Map<String, dynamic> toJson() => {
    'doc_id': docId,
    'actor_id': actorId,
    'strategy': strategy.name,
    'state': _state,
    'vv': _vv.toJson(),
    'log': _log.map((final op) => op.toJson()).toList(),
    'seen_op_ids': _seenOpIds.toList(),
    'ephemeral_state': _ephemeralState,
    'ephemeral_log': _ephemeralLog.map((final op) => op.toJson()).toList(),
  };
}
