import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'realtime_envelope.dart';

/// One decoded inbound event (or staleness signal) on a [RealtimeLink].
@immutable
final class RealtimeEvent {
  const RealtimeEvent({required this.envelope, required this.senderPeerId});

  final RealtimeEnvelope envelope;
  final String senderPeerId;

  String get type => envelope.type;
  Map<String, Object?> get payload => envelope.payload;
}

/// The client/peer half of the realtime plane (ADR 0050 §3): ONE session,
/// upgraded with the four semantics every realtime app re-implements —
///
/// 1. **Liveness**: both ends heartbeat; the link auto-acks and fires
///    [onStale] when the peer goes quiet past [staleAfter]. Staleness
///    closes the session; the consumer's policy releases whatever the
///    stream was driving.
/// 2. **Droppable sends** (`sendDroppable`): newest-wins PER TYPE — a
///    frame sent while the previous one is still in flight REPLACES it,
///    so a slow link bounds lag at one frame instead of flushing seconds
///    of stale pointers in a burst.
/// 3. **Reliable sends** (`sendReliable`): monotonic per-link sequence;
///    replays and reorder-regressions are deduped on receipt.
/// 4. **Reserved control** ([RealtimeTypes.isReserved]): heartbeats and
///    release-alls are link business — acked/handled internally, never
///    surfaced on [inbound].
///
/// App schemas stay app-owned: a [RealtimeEnvelope.payload] is a plain
/// map (vosges's gesture vocabulary is the reference shape).
///
/// Scheduling: by default the link owns its heartbeat/staleness timers.
/// With [tickDriven] it owns NONE — the consumer pulls [tick] from a loop
/// it already runs (the pulse law, ADR 0047 §4), which also makes
/// injected-clock tests deterministic.
final class RealtimeLink {
  RealtimeLink({
    required final MeshSession session,
    this.heartbeatInterval = const Duration(seconds: 2),
    this.staleAfter = const Duration(seconds: 8),
    this.clock = DateTime.now,
    this.onStale,
    this.tickDriven = false,
  }) : assert(staleAfter > heartbeatInterval),
       _session = session {
    _lastInboundAt = clock();
    _lastHeartbeatAt = clock();
    _subscription = session.inbound.listen(
      _onFrame,
      onDone: () => _die('session closed'),
      onError: (final Object _) => _die('session error'),
    );
    if (tickDriven) return;
    _heartbeat = Timer.periodic(heartbeatInterval, (final _) {
      _send(
        RealtimeEnvelope(
          type: RealtimeTypes.heartbeat,
          seq: 0,
          reliable: false,
          issuedAtMs: clock().millisecondsSinceEpoch,
        ),
      );
    });
    // Armed from birth: a peer that never speaks goes stale too, not
    // only one that goes quiet AFTER its first frame.
    _armStaleWatch();
  }

  final MeshSession _session;

  /// This link's own peer id (what the PEER sees as sender).
  String get selfPeerId => _session.remotePeerId;

  final Duration heartbeatInterval;
  final Duration staleAfter;
  final DateTime Function() clock;

  /// Fired once when the peer goes quiet past [staleAfter]; the session
  /// is closed by then.
  final void Function(String reason)? onStale;

  /// Why this link died (peer stale / session closed / session error),
  /// null while alive. lets a tick-driven consumer complete its teardown
  /// INSIDE the pulse that observed the death (a detached onStale
  /// callback races the consumer's next statement).
  String? get deathReason => _deathReason;
  String? _deathReason;

  /// Pulse-law mode: no internal timers; the consumer drives
  /// heartbeats/staleness by calling [tick] from its own loop.
  final bool tickDriven;

  DateTime? _lastInboundAt;
  DateTime? _lastHeartbeatAt;

  final _inbound = StreamController<RealtimeEvent>.broadcast();
  StreamSubscription<Uint8List>? _subscription;
  Timer? _heartbeat;
  Timer? _staleWatch;
  var _closed = false;

  var _reliableSeq = 0;
  var _lastPeerReliableSeq = -1;
  final Map<String, int> _droppableSeqs = {};
  final Map<String, RealtimeEnvelope?> _droppablePending = {};
  final Map<String, bool> _droppableSending = {};

  /// Decoded, deduped app events (reserved control excluded).
  Stream<RealtimeEvent> get inbound => _inbound.stream;

  /// Sends a droppable frame: newest-wins per [type] (see the class doc).
  Future<void> sendDroppable(
    final String type,
    final Map<String, Object?> payload,
  ) {
    assert(!RealtimeTypes.isReserved(type), 'reserved types are link-owned');
    final envelope = RealtimeEnvelope(
      type: type,
      seq: (_droppableSeqs[type] ?? 0) + 1,
      reliable: false,
      issuedAtMs: clock().millisecondsSinceEpoch,
      payload: payload,
    );
    _droppableSeqs[type] = envelope.seq;
    return _enqueueDroppable(type, envelope);
  }

  Future<void> _enqueueDroppable(
    final String type,
    final RealtimeEnvelope envelope,
  ) async {
    if (_closed) return;
    if (_droppableSending[type] == true) {
      // A send is in flight: newest wins, the older pending is dropped.
      _droppablePending[type] = envelope;
      return;
    }
    _droppableSending[type] = true;
    try {
      var next = envelope;
      while (true) {
        await _send(next);
        final queued = _droppablePending[type];
        _droppablePending[type] = null;
        if (queued == null) break;
        next = queued;
      }
    } finally {
      _droppableSending[type] = false;
    }
  }

  /// Sends a reliable frame: exactly-once semantics on receipt.
  Future<void> sendReliable(
    final String type,
    final Map<String, Object?> payload,
  ) {
    assert(!RealtimeTypes.isReserved(type), 'reserved types are link-owned');
    return _send(
      RealtimeEnvelope(
        type: type,
        seq: ++_reliableSeq,
        reliable: true,
        issuedAtMs: clock().millisecondsSinceEpoch,
        payload: payload,
      ),
    );
  }

  /// Tells the peer this link stops driving (the host clears its claim).
  Future<void> sendReleaseAll() => _send(
    RealtimeEnvelope(
      type: RealtimeTypes.releaseAll,
      seq: 0,
      reliable: true,
      issuedAtMs: clock().millisecondsSinceEpoch,
    ),
  );

  /// Pulse-law drive (only meaningful when [tickDriven]): sends a
  /// heartbeat when one is due and dies when the peer has been quiet past
  /// [staleAfter]. The consumer calls this from a loop it already runs.
  Future<void> tick() async {
    if (_closed) return;
    final now = clock();
    final lastInbound = _lastInboundAt;
    if (lastInbound != null && now.difference(lastInbound) > staleAfter) {
      _die('peer stale');
      return;
    }
    final lastHeartbeat = _lastHeartbeatAt;
    if (lastHeartbeat == null ||
        now.difference(lastHeartbeat) >= heartbeatInterval) {
      _lastHeartbeatAt = now;
      try {
        await _send(
          RealtimeEnvelope(
            type: RealtimeTypes.heartbeat,
            seq: 0,
            reliable: false,
            issuedAtMs: now.millisecondsSinceEpoch,
          ),
        );
      } on StateError {
        // The session died concurrently; [_die] handles the release path.
      }
    }
  }

  Future<void> _send(final RealtimeEnvelope envelope) async {
    if (_closed) return;
    await _session.send(envelope.encode());
  }

  void _onFrame(final Uint8List bytes) {
    if (_closed) return;
    _lastInboundAt = clock();
    if (!tickDriven) _armStaleWatch();
    final envelope = RealtimeEnvelope.tryDecode(bytes);
    if (envelope == null) return; // Foreign plane or garbage: ignored.
    switch (envelope.type) {
      case RealtimeTypes.heartbeat:
        _send(
          RealtimeEnvelope(
            type: RealtimeTypes.heartbeatAck,
            seq: 0,
            reliable: false,
            issuedAtMs: clock().millisecondsSinceEpoch,
          ),
        );
      case RealtimeTypes.heartbeatAck:
        break; // Liveness only; the timestamp above did the work.
      case RealtimeTypes.releaseAll:
        _inbound.add(
          RealtimeEvent(envelope: envelope, senderPeerId: selfPeerId),
        );
      default:
        if (envelope.reliable) {
          if (envelope.seq <= _lastPeerReliableSeq) return; // Replay dedupe.
          _lastPeerReliableSeq = envelope.seq;
        }
        _inbound.add(
          RealtimeEvent(envelope: envelope, senderPeerId: selfPeerId),
        );
    }
  }

  void _armStaleWatch() {
    _staleWatch?.cancel();
    _staleWatch = Timer(staleAfter, () => _die('peer stale'));
  }

  void _die(final String reason) {
    if (_closed) return;
    _closed = true;
    _deathReason = reason;
    _heartbeat?.cancel();
    _staleWatch?.cancel();
    _subscription?.cancel();
    unawaited(_session.close());
    onStale?.call(reason);
    _inbound.close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    _staleWatch?.cancel();
    await _subscription?.cancel();
    await _session.close();
    await _inbound.close();
  }
}
