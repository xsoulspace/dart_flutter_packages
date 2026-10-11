import 'package:meta/meta.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';

/// The minimal replica seam the [DeltaPlanner] needs (ADR 0010 §4's
/// decision logic, made pure).
///
/// Kept deliberately narrow: version vector, pending ops, the kernel's
/// `opsSince`/`needsSnapshotFor` diff seam, and snapshot production. The
/// kernel's `ConvergenceDoc` exposes exactly these members, so wrapping
/// one is a one-line adapter — the kernel itself stays free of any
/// session-layer interface.
abstract interface class DeltaReplica {
  /// Identity used to look the doc up in the peer's announced vectors.
  String get docId;

  /// This replica's anti-entropy header for the document.
  VersionVector get vv;

  /// Ops retained for delta shipping (not yet compacted).
  List<OpRecord> get pendingOps;

  /// Ops this replica holds that [remoteVv] has not observed.
  List<OpRecord> opsSince(final VersionVector remoteVv);

  /// True when [remoteVv] is fully covered but the log was compacted away
  /// under it — only a snapshot can serve the peer.
  bool needsSnapshotFor(final VersionVector remoteVv);

  /// The current state as a snapshot at this replica's watermark.
  Snapshot snapshotFor();
}

/// What to send one peer in a delta frame: ops first, snapshots where the
/// op log can no longer serve.
@immutable
final class DeltaPlan {
  const DeltaPlan({required this.ops, required this.states});

  /// Ops to ship, in the order they should appear on the wire.
  final List<OpRecord> ops;

  /// Snapshots to ship for documents whose state the op log cannot serve.
  final List<Snapshot> states;

  /// True when nothing would go out for this peer.
  bool get isEmpty => ops.isEmpty && states.isEmpty;
}

/// Pure delta planner (ADR 0010 §4's per-document decision, extracted from
/// the mesh exchange so every anti-entropy session plans identically).
///
/// Stateless and transport-free: given the documents to consider (in the
/// caller's delivery order) and the peer's per-document version vectors,
/// it decides per document —
///
/// - the peer never announced the doc (`remoteVectors[docId]` null):
///   ship the pending ops, or a snapshot when the log is empty;
/// - the peer lags: ship the ops it has not observed (`opsSince`);
/// - the peer is covered but the log was compacted
///   (`needsSnapshotFor`): ship a snapshot;
/// - the peer is up to date: ship nothing.
///
/// An optional [DeltaPlan]-level `maxOps` budget (receiver-expressed
/// backpressure-lite, ADR 0048 §2) stops the walk before a document once
/// the ops sent so far have reached it — the remainder arrives on a later
/// exchange.
final class DeltaPlanner {
  const DeltaPlanner();

  /// Plans the outgoing delta for [docs], considered in the given order.
  ///
  /// Order matters twice: it decides which documents get the budget first,
  /// and it is preserved inside [DeltaPlan.ops] (callers sort by the
  /// receiver's expressed priority before calling).
  DeltaPlan plan({
    required final Iterable<DeltaReplica> docs,
    required final Map<String, VersionVector> remoteVectors,
    final int? maxOps,
  }) {
    final ops = <OpRecord>[];
    final states = <Snapshot>[];
    for (final doc in docs) {
      if (maxOps != null && ops.length >= maxOps) break;
      final theirs = remoteVectors[doc.docId];
      if (theirs == null) {
        if (doc.pendingOps.isNotEmpty) {
          ops.addAll(doc.pendingOps);
        } else {
          states.add(doc.snapshotFor());
        }
      } else {
        final missing = doc.opsSince(theirs);
        if (missing.isNotEmpty) {
          ops.addAll(missing);
        } else if (doc.needsSnapshotFor(theirs)) {
          states.add(doc.snapshotFor());
        }
      }
    }
    return DeltaPlan(ops: ops, states: states);
  }
}
