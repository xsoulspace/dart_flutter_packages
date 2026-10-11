import 'package:universal_storage_convergence/universal_storage_convergence.dart';

/// The high-water HLC of everything this replica has RECEIVED — remote ops
/// via `applyRemote`, an adopted snapshot's `createdAt`, a restored
/// persisted log — and therefore the causality floor for later local
/// writes.
///
/// WHY this exists: the kernel's `ConvergenceDoc.applyRemote` folds remote
/// ops but never ticks the local clock, and LWW orders by
/// `(wallMillis, counter, actorId)`. A peer with an ahead wall clock can
/// issue ops that outrank every local write made afterwards on a slower
/// clock — forever. The fix (the receive rule, proven in last_answer's
/// `headless_core` DocReplica): on every delivery, absorb the remote
/// timestamp into a watermark with `Hlc.receive` — which keeps THIS
/// replica's actor id and stays strictly above both inputs — and hand the
/// watermark back to the kernel as `applyLocal`'s `lastIssued`. A local
/// write issued after folding a remote op then always orders after it,
/// even on a frozen wall clock.
///
/// The watermark is raise-only: observing an older event never lowers it,
/// and re-observing the newest known event is a no-op.
final class ReceiveWatermark {
  ReceiveWatermark({required this.actorId});

  /// Restores a persisted watermark (see [toJson]). The actor id must be
  /// the replica's own — a restored watermark keeps issuing under this
  /// replica's identity.
  factory ReceiveWatermark.fromJson(final Map<String, dynamic> json) =>
      ReceiveWatermark._(
        json['actor_id'] as String,
        json['value'] == null
            ? null
            : Hlc.fromJson(
                Map<String, dynamic>.from(
                  json['value'] as Map<dynamic, dynamic>,
                ),
              ),
      );

  ReceiveWatermark._(this.actorId, this._value);

  /// The replica's own actor id; absorbed deliveries keep it, so later
  /// local ops issue op ids under this replica's identity (a foreign-actor
  /// watermark would collide with the remote's ids in kernel dedupe).
  final String actorId;

  Hlc? _value;

  /// The current watermark; null before anything was ever received or
  /// restored.
  Hlc? get value => _value;

  /// Absorbs one received event ([remote]) into the watermark.
  ///
  /// Raise-only: when the watermark already covers [remote], this is a
  /// no-op — restoration and redelivery can never regress the clock.
  ///
  /// PURELY LOGICAL, on purpose: the watermark is the (wall, counter) max
  /// of what this replica has RECEIVED, re-anchored to [actorId]. It never
  /// consults the host clock. Anchoring receives to real time (the
  /// textbook HLC receive) silently re-bases the watermark to the host's
  /// wall clock — harmless when every replica's clock is truthful, but
  /// wrong the moment clocks are fabricated (tests, simulations) or
  /// skewed (offline devices): a receive would drag the watermark to the
  /// host's "now" and reorder LWW outcomes for writes issued on any other
  /// clock. Observed in the wild: last_answer's task-board suite pins this
  /// (found during the ecsly ADR 0004 adoption, 2026-10-11). The
  /// issue-time strictness instead comes from the kernel's `lastIssued`
  /// tick seam — see [floorNow].
  void observe(final Hlc remote) {
    final current = _value;
    if (current != null &&
        (current.wallMillis > remote.wallMillis ||
            (current.wallMillis == remote.wallMillis &&
                current.counter >= remote.counter))) {
      return;
    }
    _value = Hlc(remote.wallMillis, remote.counter, actorId);
  }

  /// Absorbs an adopted snapshot's creation timestamp, so local writes
  /// after adopting wholesale snapshot state order after the snapshot's
  /// content.
  void observeSnapshot(final Snapshot snapshot) => observe(snapshot.createdAt);

  /// Floors the time handed to the next local write at the watermark's
  /// wall clock: a `now` below the watermark comes back raised to it, a
  /// `now` at or above it passes through untouched.
  ///
  /// This bounds the WALL component only — strict ordering above received
  /// events comes from also passing [value] as the kernel's `lastIssued`
  /// (the counter seam). Use both together; [floorNow] alone cannot
  /// outrank a same-wall, higher-counter remote op.
  DateTime floorNow(final DateTime now) {
    final current = _value;
    if (current == null) return now;
    if (now.millisecondsSinceEpoch < current.wallMillis) {
      return DateTime.fromMillisecondsSinceEpoch(current.wallMillis);
    }
    return now;
  }

  /// Full serialization for durable local persistence.
  Map<String, dynamic> toJson() => {
    'actor_id': actorId,
    if (_value != null) 'value': _value!.toJson(),
  };
}
