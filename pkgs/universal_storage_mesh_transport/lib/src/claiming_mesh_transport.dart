import 'dart:async';
import 'dart:typed_data';

import 'mesh_peer.dart';
import 'mesh_transport.dart';

/// Routes each inbound session to exactly one of two consumers by the
/// CONTENT of its first inbound frame (ADR 0047 consumer story: one LAN
/// server, two planes).
///
/// A single LAN server often carries several PLANES — realtime frames
/// (latency-critical, ephemeral) and durable world-sync frames
/// (anti-entropy, self-identifying). A path or port split cannot survive
/// session wrappers that re-wrap the raw socket (AEAD seal layers expose
/// only [MeshSession]), but frame CONTENT reaches every wrapper decrypted,
/// and the mesh-sync protocol sends its `hello` before anything else — so
/// the first frame of a session reliably declares its plane.
///
/// Ownership law: sealed sessions are the SOLE owner of their raw byte
/// stream (single-subscription), so this wrapper subscribes exactly once
/// per session and re-broadcasts to the routed consumer. Until the first
/// frame arrives (or [claimTimeout] elapses) the session parks in neither
/// consumer; a session that dies before its first frame is dropped, not
/// routed — a dead session belongs to no plane.
///
/// ```dart
/// final planes = ClaimingMeshTransport(
///   inner: sealedTransport,
///   claim: looksLikeSyncHello, // first-frame predicate
/// );
/// worldSync.attachTransport(planes);            // claimed plane
/// gestureHost = MultiSenderHost(transport: planes.passthrough, ...);
/// ```
final class ClaimingMeshTransport implements MeshTransport {
  ClaimingMeshTransport({
    required final MeshTransport inner,
    required final bool Function(Uint8List firstFrame) claim,
    this.claimTimeout = const Duration(seconds: 10),
  }) : _inner = inner,
       _claim = claim {
    _subscription = inner.incoming.listen(_park);
  }

  final MeshTransport _inner;
  final bool Function(Uint8List firstFrame) _claim;

  /// How long a silent session parks before routing to [passthrough]. The
  /// realtime host's own staleness policy applies after routing, so the
  /// timeout only needs to exceed the planes' normal first-frame latency
  /// (a heartbeat within seconds on the realtime plane, hello-on-connect
  /// for sync dials).
  final Duration claimTimeout;

  // Single-subscription: each plane has exactly one consumer, and events
  // emitted before that consumer attaches must buffer, never drop.
  final _claimed = StreamController<MeshSession>();
  final _rejected = StreamController<MeshSession>();
  StreamSubscription<MeshSession>? _subscription;
  final Set<_ParkedSession> _parked = <_ParkedSession>{};

  /// CLAIMED sessions only: the first inbound frame satisfied [claim].
  @override
  Stream<MeshSession> get incoming => _claimed.stream;

  /// Outbound dials are plane-neutral: both consumers may dial the same
  /// inner transports (a client dials the sync plane by simply speaking
  /// sync first on its session).
  @override
  Future<MeshSession> connect(final MeshPeerRecord peer) =>
      _inner.connect(peer);

  /// Transport view over the NOT-claimed sessions (rejected plane, or
  /// silent past [claimTimeout]). The realtime consumer attaches here.
  MeshTransport get passthrough => _PassthroughTransport(this);

  void _park(final MeshSession session) {
    final parked = _ParkedSession._(session, this);
    _parked.add(parked);
    parked._start();
  }

  void _route(final _ParkedSession parked, final bool claimed) {
    _parked.remove(parked);
    if (claimed) {
      _claimed.add(parked);
    } else {
      _rejected.add(parked);
    }
  }

  /// Cancels the inner subscription and closes every still-parked session
  /// (neither consumer ever sees them). Attached consumers keep their
  /// streams open until they close them.
  Future<void> dispose() async {
    await _subscription?.cancel();
    for (final parked in List.of(_parked)) {
      await parked._abandon();
    }
    await _claimed.close();
    await _rejected.close();
  }
}

final class _PassthroughTransport implements MeshTransport {
  _PassthroughTransport(this._owner);

  final ClaimingMeshTransport _owner;

  @override
  Stream<MeshSession> get incoming => _owner._rejected.stream;

  @override
  Future<MeshSession> connect(final MeshPeerRecord peer) =>
      _owner._inner.connect(peer);
}

/// One session parked between arrival and its first frame. Owns the inner
/// session's inbound stream exclusively; after routing it is a plain
/// byte-forwarding [MeshSession].
final class _ParkedSession implements MeshSession {
  _ParkedSession._(this._inner, this._owner);

  final MeshSession _inner;
  final ClaimingMeshTransport _owner;

  final _outbound = StreamController<Uint8List>();
  final List<Uint8List> _buffer = <Uint8List>[];
  StreamSubscription<Uint8List>? _subscription;
  Timer? _timer;
  var _routed = false;
  var _dead = false;
  var _outboundSealed = false;

  @override
  String get remotePeerId => _inner.remotePeerId;

  @override
  Stream<Uint8List> get inbound => _outbound.stream;

  void _start() {
    _timer = Timer(_owner.claimTimeout, () => _route(false));
    _subscription = _inner.inbound.listen(
      _onFrame,
      onDone: _onDone,
      onError: (final Object _) => _onDone(),
    );
  }

  void _onFrame(final Uint8List frame) {
    if (_routed) {
      _forward(frame);
      return;
    }
    _route(_owner._claim(frame));
    // The deciding frame itself must reach the consumer (the sync
    // exchange's hello IS the claiming frame).
    _forward(frame);
  }

  void _route(final bool claimed) {
    if (_routed) return;
    _routed = true;
    _timer?.cancel();
    _timer = null;
    _owner._route(this, claimed);
  }

  void _onDone() {
    if (_routed) {
      _outbound.close();
      return;
    }
    // Died before declaring its plane: drop, never route (a dead session
    // belongs to no plane).
    _dead = true;
    _timer?.cancel();
    _owner._parked.remove(this);
  }

  void _forward(final Uint8List frame) {
    if (!_dead && !_outboundSealed) _outbound.add(frame);
  }

  @override
  Future<void> send(final Uint8List payload) => _inner.send(payload);

  @override
  Future<void> close() async {
    final wasRouted = _routed;
    if (!wasRouted && !_dead) {
      // Closed before declaring its plane: no consumer has seen it — drop
      // it exactly like a session that died before its first frame.
      _dead = true;
      _owner._parked.remove(this);
    }
    _timer?.cancel();
    if (!wasRouted) await _subscription?.cancel();
    await _closeOutbound();
    if (wasRouted) {
      // The inner session still has our listener: its done event is
      // deliverable, so the close future completes.
      await _inner.close();
    } else {
      // Pre-route teardown: our cancel may have removed the only listener
      // the inner stream had, and a listenerless done event never
      // completes — close best-effort, never hang the disposer.
      unawaited(_inner.close());
    }
  }

  /// Closing a [StreamController] nobody ever listened to never completes
  /// (the done event has no subscriber); abandoned sessions skip the await
  /// and just stop accepting frames.
  Future<void> _closeOutbound() async {
    if (_outbound.hasListener) {
      await _outbound.close();
    } else {
      _outboundSealed = true;
    }
  }

  /// Dispose-time teardown of a session that never declared its plane.
  /// Best-effort by law: disposal must never hang on a transport quirk.
  Future<void> _abandon() async {
    _timer?.cancel();
    _dead = true;
    _owner._parked.remove(this);
    await _subscription?.cancel();
    await _closeOutbound();
    unawaited(_inner.close());
  }
}
