import 'dart:async';

import 'package:meta/meta.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'ephemeral_frame_auth.dart';
import 'ephemeral_frame_transport.dart';
import 'mesh_presence_tracker.dart';
import 'presence_config.dart';

/// Wall clock used for stamps and sweeps; injectable for tests.
typedef PresenceClock = DateTime Function();

/// Why an inbound frame was dropped as named data (ADR 0031 §3): dropped
/// frames are counted and reported, never folded.
enum MeshFrameRejectionReason {
  /// The frame carried no signature at all.
  unsigned,

  /// The signature did not verify against the registered identity key of
  /// the claimed sender (unknown peer, tampered payload, or forged
  /// signature).
  unauthenticated,
}

/// One dropped (never folded) inbound frame, kept for observability.
@immutable
final class MeshFrameRejection {
  const MeshFrameRejection({required this.frame, required this.reason});

  /// The dropped frame. Inspection only — folding it is forbidden (ADR
  /// 0031 §3).
  final MeshEphemeralFrame frame;

  final MeshFrameRejectionReason reason;

  @override
  String toString() =>
      'MeshFrameRejection(${frame.event} from ${frame.fromPeerId} '
      'on ${frame.docId}: ${reason.name})';
}

/// App-owned presence session over ANY [EphemeralFrameTransport]
/// (ADR 0031 §1–2): join on open, leave on close, ping on activity, ttl
/// sweep as the crash backstop. Feeds [MeshPresenceTracker] — the kernel
/// fold stays exactly where it is.
///
/// The session is channel-scoped: [docId] is the opaque frame channel
/// ("this document is open here" is one embedding of it). Nothing here
/// knows about documents, worlds, or any host app.
///
/// Frame authentication (ADR 0031 §3): outgoing frames are signed when a
/// [signer] is configured; inbound frames are verified against registered
/// peer identity keys via [authenticator] BEFORE the tracker folds.
/// Unauthenticated or tampered frames are dropped as named data —
/// counted in [rejectedFrameCount], listed in [rejections], never folded.
///
/// ```dart
/// final session = MeshPresenceSession(
///   transport: relayEphemeralTransport,
///   tracker: tracker,
///   docId: 'doc/1',
/// );
/// await session.open();          // join
/// session.notifyActivity();      // ping on activity
/// await session.close();         // leave
/// ```
final class MeshPresenceSession {
  MeshPresenceSession({
    required this.transport,
    required this.tracker,
    required this.docId,
    this.presenceConfig = PresenceConfig.interactive,
    this.signer,
    this.authenticator,
    PresenceClock? clock,
  }) : _clock = clock ?? _systemClock;

  static DateTime _systemClock() => DateTime.now();

  final EphemeralFrameTransport transport;

  final MeshPresenceTracker tracker;

  /// Opaque frame channel this session is present on.
  final String docId;

  /// Cadence policy with bounds; the interval adapts to activity WITHIN
  /// the preset bounds and every frame's ttl obeys the invariant
  /// `ttl = ttlFactor × pingInterval` (ADR 0031 §5).
  final PresenceConfig presenceConfig;

  /// Signs outgoing frames with the local identity keypair; `null` means
  /// outgoing frames are unsigned (receivers with an authenticator drop
  /// them).
  final EphemeralFrameSigner? signer;

  /// Verifies inbound frames against registered peer identity keys
  /// before folding; `null` disables the check (the tracker's
  /// forged-actor guard remains as defense-in-depth).
  final EphemeralFrameAuthenticator? authenticator;

  final PresenceClock _clock;

  Timer? _pingTimer;
  StreamSubscription<MeshEphemeralFrame>? _framesSub;
  Future<void> _inbound = Future<void>.value();
  var _open = false;
  var _activeSinceLastPing = false;
  DateTime? _lastPingAt;
  final List<MeshFrameRejection> _rejections = [];

  /// Whether [open] ran without a matching [close].
  bool get isOpen => _open;

  /// How many inbound frames were dropped as named data (ADR 0031 §3).
  int get rejectedFrameCount => _rejections.length;

  /// Every dropped frame with its rejection reason, oldest first.
  List<MeshFrameRejection> get rejections => List.unmodifiable(_rejections);

  /// Joins the channel: announces presence, starts listening for peer
  /// frames, and starts the adaptive ping/sweep cycle.
  Future<void> open({
    final DateTime? now,
    final Map<String, Object?> details = const {},
  }) async {
    if (_open) return;
    _open = true;
    _framesSub = transport.frames.listen(_onFrame);
    await _announce(
      MeshEphemeralEvent.join,
      now: now,
      details: details,
      ttl: _ttlFor(interval: presenceConfig.pingInterval(active: false)),
    );
    _schedulePing();
  }

  /// Leaves the channel: announces [MeshEphemeralEvent.leave] so peers
  /// drop this peer immediately (their ttl sweep is the backstop when
  /// this never runs — a crash, say), then stops timers and listening.
  Future<void> close({final DateTime? now}) async {
    if (!_open) return;
    _open = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _framesSub?.cancel();
    _framesSub = null;
    await _announce(MeshEphemeralEvent.leave, now: now);
  }

  /// Explicit liveness refresh (also used by the internal cycle).
  Future<void> ping({
    final DateTime? now,
    final Map<String, Object?> details = const {},
  }) async {
    if (!_open) return;
    _lastPingAt = now ?? _clock();
    await _announce(
      MeshEphemeralEvent.ping,
      now: now,
      details: details,
      ttl: _ttlFor(interval: presenceConfig.pingInterval(active: true)),
    );
  }

  /// Activity hook (ADR 0031 §5: ping on activity): marks the session
  /// active — the next cycle pings at the preset's shortest interval —
  /// and pings immediately when the last ping is older than
  /// [PresenceConfig.minPingInterval] (throttled so bursts cannot flood).
  Future<void> notifyActivity({final DateTime? now}) async {
    if (!_open) return;
    _activeSinceLastPing = true;
    final at = now ?? _clock();
    final last = _lastPingAt;
    if (last == null || at.difference(last) >= presenceConfig.minPingInterval) {
      await ping(now: at);
    }
  }

  /// Expires past-ttl entries from the tracker; returns how many were
  /// dropped. Also run by the internal cycle every ping interval — ttl is
  /// the crash backstop (ADR 0031 §1), not a polling requirement.
  int sweep({final DateTime? now}) => tracker.sweep(now ?? _clock());

  // -- Internals -----------------------------------------------------------

  Duration _ttlFor({required final Duration interval}) =>
      presenceConfig.ttlFor(interval);

  Future<void> _announce(
    final MeshEphemeralEvent event, {
    final DateTime? now,
    final Duration? ttl,
    final Map<String, Object?> details = const {},
  }) async {
    final at = now ?? _clock();
    var frame = tracker.announce(
      docId: docId,
      event: event,
      now: at,
      ttl: ttl ?? _ttlFor(interval: presenceConfig.maxPingInterval),
      details: details,
    );
    final localSigner = signer;
    if (localSigner != null) {
      frame = frame.withSignature(await localSigner.sign(frame));
    }
    await transport.send(frame);
  }

  void _schedulePing([final Duration? interval]) {
    _pingTimer?.cancel();
    if (!_open) return;
    _pingTimer = Timer(
      interval ?? presenceConfig.pingInterval(active: _activeSinceLastPing),
      _onPingTimer,
    );
  }

  Future<void> _onPingTimer() async {
    if (!_open) return;
    // Decide the NEXT interval first: the ttl stamped on this ping must
    // cover the gap to the next one (a peer expires after ~ttlFactor
    // missed pings).
    final nextInterval = presenceConfig.pingInterval(
      active: _activeSinceLastPing,
    );
    _activeSinceLastPing = false;
    tracker.sweep(_clock());
    await _announce(
      MeshEphemeralEvent.ping,
      now: _clock(),
      ttl: _ttlFor(interval: nextInterval),
    );
    _schedulePing(nextInterval);
  }

  void _onFrame(final MeshEphemeralFrame frame) {
    // Serialize processing so verification + fold order matches arrival.
    _inbound = _inbound.then((_) => _processFrame(frame));
  }

  Future<void> _processFrame(final MeshEphemeralFrame frame) async {
    if (!_open || frame.docId != docId) return;
    if (frame.fromPeerId == tracker.actorId) return; // local echo
    final localAuthenticator = authenticator;
    if (localAuthenticator != null) {
      final authentic = await localAuthenticator.verify(frame);
      if (!authentic) {
        _rejections.add(
          MeshFrameRejection(
            frame: frame,
            reason: frame.signature == null
                ? MeshFrameRejectionReason.unsigned
                : MeshFrameRejectionReason.unauthenticated,
          ),
        );
        return; // dropped as named data — never folded (ADR 0031 §3)
      }
    }
    tracker.handleFrame(frame, now: _clock());
  }
}
